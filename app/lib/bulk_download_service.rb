##
# BulkDownloadService: helper class for generating curl configuration files for initiating bulk downloads from
# keyword and faceted search

class BulkDownloadService

  # Generate a String representation of a configuration file containing URLs and output paths to pass to
  # curl for initiating bulk downloads
  #
  # * *params*
  #   - +study_files+ (Array<StudyFile>) => Array of StudyFiles to be downloaded
  #   - +directory_files+ (Array<Hash>) => Array of file descriptors in a bucket folder (from get_requested_directory_files)
  #   - +user+ (User) => User requesting download
  #   - +study_bucket_map+ => Map of study IDs to bucket names
  #   - +output_pathname_map+ => Map of study file IDs to output pathnames
  #
  # * *return*
  #   - (String) => String representation of signed URLs and output filepaths to pass to curl
  def self.generate_curl_configuration(study_files:,
                                       directory_files: [],
                                       user:,
                                       study_bucket_map:,
                                       output_pathname_map:)
    curl_configs = ['--create-dirs', '--compressed']
    # create an array of all objects to be downloaded, including directory files
    download_objects = study_files.to_a + directory_files
    # Get signed URLs for all files in the requested download objects
    Parallel.map(download_objects, in_threads: 100) do |download_object|
      client = FireCloudClient.new
      curl_configs << self.get_single_curl_command(file: download_object, fc_client: client, user: user,
                                                   study_bucket_map: study_bucket_map, output_pathname_map: output_pathname_map)
    end
    studies = study_files.map(&:study).uniq
    study_manifest_paths = studies.map do |study|
      "#{Rails.application.routes.url_helpers.manifest_api_v1_study_path(study)}"
    end
    half_hour = 1800
    totat = user.create_totat(half_hour, study_manifest_paths)
    studies.map do |study|
      manifest_config = ""
      if Rails.env.development?
        # if we're in development, allow not checking the cert
        manifest_config += "-k\n"
      end
      manifest_path = RequestUtils.get_base_url + Rails.application.routes.url_helpers.manifest_api_v1_study_path(study)
      include_dirs = directory_files.any?
      manifest_config += "url=\"#{manifest_path}?auth_code=#{totat[:totat]}&include_dirs=#{include_dirs}\"\n"
      manifest_config += "output=\"#{study.accession}/file_supplemental_info.tsv\""
      curl_configs << manifest_config
    end
    curl_configs.join("\n\n")
  end

  # Update a user's download quota after assembling the list of files requested
  # Since the download happens outside the purview of the portal, the quota impact is front-loaded
  #
  # * *params*
  #   - +user+ (User) => User performing bulk download action
  #   - +files+ (Array<StudyFile>) => Array of files requested
  #   - +files+ (Array<DirectoryListing>) => Array of files requested in DirectoryListings
  #
  # * *raises*
  #   - (RuntimeError) => User download quota exceeded
  def self.update_user_download_quota(user:, files:, directories: [])
    download_quota = ApplicationController.get_download_quota
    file_bytes_requested = files.map(&:upload_file_size).compact.reduce(0, :+)
    dir_bytes_requested = directories.map(&:total_bytes).reduce(0, :+)
    bytes_requested = file_bytes_requested + dir_bytes_requested
    bytes_allowed = download_quota - user.daily_download_quota
    if bytes_requested > bytes_allowed
      raise RuntimeError.new "Total file size exceeds user download quota: #{bytes_requested} bytes requested, #{bytes_allowed} bytes allowed"
    else
      Rails.logger.info "Adding #{bytes_requested} bytes to user: #{user.id} download quota for bulk download"
      user.daily_download_quota += bytes_requested
      user.save
    end
  end

  # Get an array of permitted study accessions based off of the query & a user's view permissions
  # Takes into account DownloadAgreement restrictions as well
  #
  # * *params*
  #   - +study_accessions+ (Array<String>) => Array of requested study accessions
  #   - +user+ (User) => User requesting download
  #
  # * *returns*
  #   - Hash( key=> Array<String>) Hash categorizing the requested accessions as
  #       valid, lacks_acceptance, or forbidden
  def self.get_permitted_accessions(study_accessions:, user:)
    viewable_accessions = Study.viewable(user).pluck(:accession)
    permitted_accessions = study_accessions & viewable_accessions
    user_lacks_acceptance = []
    # collect array of study accession requiring acceptance of download agreement (checking for expiration)
    agreement_accessions = []
    DownloadAgreement.all.each do |agreement|
      agreement_accessions << agreement.study.accession unless agreement.expired?
    end
    requires_agreement = permitted_accessions & agreement_accessions
    if requires_agreement.any?
      requires_agreement.each do |accession|
        user_lacks_acceptance << accession unless DownloadAcceptance.where(study_accession: accession, email: user.email).exists?
      end
      permitted_accessions -= user_lacks_acceptance
    end
    { permitted: permitted_accessions,
      lacks_acceptance: user_lacks_acceptance,
      forbidden: study_accessions - viewable_accessions}
  end

  # Get an array of StudyFiles from matching StudyAccessions and file_types
  #
  # * *params*
  #   - +file_types+ (Array<String>) => Array of requested file types to be ingested
  #   - +study_accessions+ (Array<String>) => Array of StudyAccession values from which to pull files
  #
  # * *return*
  #   - (Array<StudyFile>) => Array of StudyFiles to pass to #generate_curl_config
  def self.get_requested_files(file_types: [], study_accessions:)
    # if 'None' is requested type, exit immediately as this is only for a single folder download
    return [] if file_types == ['None']
    # replace 'Expression' with both dense & sparse matrix file types
    # include bundled 10X files as well to avoid MongoDB timeout issues when trying to load bundles
    if file_types.include?('Expression')
      file_types.delete_if {|file_type| file_type == 'Expression'}
      file_types += ['Expression Matrix', 'MM Coordinate Matrix', '10X Genes File', '10X Barcodes File']
    end

    studies = Study.where(:accession.in => study_accessions)
    # get requested files, excluding externally stored sequence data
    base_file_selector = StudyFile.where(human_fastq_url: nil, :study_id.in => studies.pluck(:id))
    file_types.present? ? base_file_selector.where(:file_type.in => file_types) : base_file_selector
  end

  # get all requested files from matching DirectoryListings
  #
  # * *params*
  #   - +directories+ (Mongoid::Critera) => selector mapping to requested DirectoryListings from a study
  #
  # * *returns*
  #   - (Array<Hash>) => {name: name/relative location of file in bucket, study_id: id of study}
  def self.get_requested_directory_files(directories)
    dir_files = []
    directories.each do |directory|
      directory.files.each do |file|
        dir_file = {
          name: file[:name],
          study_id: directory.study.id.to_s
        }.with_indifferent_access
        dir_files << dir_file
      end
    end
    dir_files
  end

  # Get a preview of the number of files/total bytes by StudyAccession and file_type
  #
  # * *params*
  #   - +file_types+ (Array<String>) => Array of requested file types to be ingested
  #   - +study_accessions+ (Array<String>) => Array of StudyAccession values from which to pull files
  #
  # * *return*
  #   - (Hash) => Hash of StudyFile::BULK_DOWNLOAD_TYPES matching query w/ number of files and total bytes
  def self.get_requested_file_sizes_by_type(file_types: [], study_accessions:)
    # replace 'Expression' with both dense & sparse matrix file types
    requested_files = get_requested_files(file_types: file_types, study_accessions: study_accessions)
    files_by_type = {}
    requested_types = requested_files.map(&:simplified_file_type).uniq
    requested_types.each do |req_type|
      files = requested_files.select {|file| file.simplified_file_type == req_type}
      files_by_type[req_type] = {total_files: files.size, total_bytes: files.map(&:upload_file_size).compact.reduce(:+)}
    end
    files_by_type
  end

  # Get a preview of the number of files/total bytes by DirectoryListing name (single study)
  #
  # * *params*
  #   - +directories+ (Array<DirectoryListing>, Mongoid::Criteria) => Array of requested directories
  #
  # * *returns*
  #   - (Hash) => Hash of directory names to total_files & total_bytes
  def self.get_requested_directory_sizes(directories)
    directories_by_name = {}
    directories.each do |directory|
      directories_by_name[directory.name] = {
        total_bytes: directory.total_bytes,
        total_files: directory.files.count
      }
    end
    directories_by_name
  end

  # Generate a String representation of a configuration file containing URLs and output paths to pass to
  # curl for initiating bulk downloads
  #
  # * *params*
  #   - +file+ (StudyFile, Hash) => file object to be downloaded
  #   - +fc_client+ (FireCloudClient) => Client to call GCS and generate signed_url
  #   - +user+ (User) => User requesting download
  #   - +study_bucket_map+ => Map of study IDs to bucket names
  #   - +output_pathname_map+ => Map of study file IDs to output pathnames
  #
  # * *return*
  #   - (String) => String representation of single signed URL and output filepath to pass to curl
  def self.get_single_curl_command(file:, fc_client:, user:, study_bucket_map:, output_pathname_map:)
    fc_client ||= ApplicationController.firecloud_client
    # if a file is a StudyFile, use bucket_location, otherwise the :name key will contain its location (if DirectoryListing)
    if file.is_a?(StudyFile)
      file_location = file.bucket_location
      bucket_name = study_bucket_map[file.study_id.to_s]
      output_path = output_pathname_map[file.id.to_s]
    elsif file.is_a?(Hash)
      file_location = file[:name]
      bucket_name = study_bucket_map[file[:study_id]]
      output_path = output_pathname_map[file[:name]]
    end

    begin
      signed_url = fc_client.execute_gcloud_method(:generate_signed_url, 0, bucket_name, file_location,
                                                   expires: 1.day.to_i) # 1 day in seconds, 86400
      curl_config = [
          'url="' + signed_url + '"',
          'output="' + output_path + '"'
      ]
    rescue => e
      error_context = ErrorTracker.format_extra_context(file, {storage_bucket: bucket_name})
      ErrorTracker.report_exception(e, user, error_context)
      Rails.logger.error "Error generating signed url for #{output_path}; #{e.message}"
      curl_config = [
          '# Error downloading ' + output_path + '.  ' +
              'Did you delete the file in the bucket and not sync it in Single Cell Portal?'
      ]
    end
    curl_config.join("\n")
  end

  # generate a map of study ids => GCS bucket names to avoid Mongo query timeouts when parallelizing curl command generation
  #
  # * *params*
  #   - +study_accessions+ (Array<String>) => Array of StudyAccession values from which to pull ids/bucket names
  #
  # * *returns*
  #   - (Hash<String, String>) => Map of study IDs to bucket names
  def self.generate_study_bucket_map(study_accessions)
    Hash[Study.where(:accession.in => study_accessions).map {|study| [study.id.to_s, study.bucket_id]}]
  end

  # generate a map of study file ids => output pathnames to avoid Mongo query timeouts when parallelizing curl command generation
  #
  # * *params*
  #   - +study_files+ (Array<StudyFile>) => Array of StudyFiles to be downloaded
  #   - +directories+ (Array<DirectoryListing>) => Array of DirectoryListings to be downloaded
  #
  # * *returns*
  #   - (Hash<String, String>) => Map of study file IDs to output pathnames
  def self.generate_output_path_map(study_files, directories=[])
    output_map = {}
    study_files.each do |study_file|
      output_map[study_file.id.to_s] = study_file.bulk_download_pathname
    end
    directories.each do |directory|
      directory.files.each do |file|
        output_map[file[:name]] = directory.bulk_download_pathname(file)
      end
    end
    output_map
  end

  # generate a study_info object from an existing study
  def self.generate_study_manifest(study, include_dirs=false)
    info = HashWithIndifferentAccess.new
    info[:study] = {
      name: study.name,
      description: study.description.try(:truncate, 150),
      accession: study.accession,
      cell_count: study.cell_count,
      gene_count: study.gene_count,
      link: RequestUtils.get_base_url + Rails.application.routes.url_helpers.view_study_path(accession: study.accession, study_name: study.name)
    }
    info[:files] = study.study_files
                        .where(queued_for_deletion: false)
                        .map{|f| generate_study_file_manifest(f)}
    if include_dirs
      info[:directories] = study.directory_listings.are_synced
                                .map {|d| generate_directory_listing_manifest(d)}
    end
    info
  end

  # generate a study_info.json object from an existing study_file
  def self.generate_study_file_manifest(study_file)
    output = {
      filename: study_file.upload_file_name,
      file_type: study_file.file_type
    }

    if study_file.expression_file_info
      output[:expression_file_info] = {}
      study_file.expression_file_info.attributes.each  do |key, value|
        output[:expression_file_info][key] = value
      end
    end
    if study_file.taxon
      output[:species_scientific_name] = study_file.taxon.scientific_name
    end
    if study_file.genome_assembly
      output[:genome_assembly_name] = study_file.genome_assembly.name
      output[:genome_assembly_accession] = study_file.genome_assembly.accession
    end
    if study_file.genome_annotation
      output[:genome_annotation_name] = study_file.genome_annotation.name
    end
    output
  end

  # generate a study_info.json object from an existing directory_listing
  def self.generate_directory_listing_manifest(directory_listing)
    output = []
    directory_listing.files.each do |file|
      entry = {
        filename: directory_listing.bulk_download_folder(file),
        file_type: directory_listing.file_type,
        species_scientific_name: directory_listing.taxon.try(:scientific_name)
      }
      output << entry
    end
    output
  end

  # takes a study manifest file (from generate_study_manifest) and makes a tsv.
  # Once the tsv format stabilizes for a couple of months, it will probably be best
  # to update the synthetic studies seed file format to the tsv format (if possible)
  # and consolidate this and the above methods.
  # include_dirs governs whether or not to include directory listing objects in manifest
  def self.generate_study_files_tsv(study, include_dirs=false)
    study_manifest = generate_study_manifest(study, include_dirs)
    col_names_and_paths = [
      {filename: 'filename'},
      {file_type: 'file_type'},
      {species_scientific_name: 'species_scientific_name'},
      {genome_assembly_name: 'genome_assembly_name'},
      {genome_assembly_accession: 'genome_assembly_accession'},
      {genome_annotation_name: 'genome_annotation_name'},
      {is_raw_counts: 'expression_file_info.is_raw_counts'},
      {library_preparation_protocol: 'expression_file_info.library_preparation_protocol'},
      {units: 'expression_file_info.units'},
      {biosample_input_type: 'expression_file_info.biosample_input_type'},
      {modality: 'expression_file_info.modality'}
    ]

    col_names = col_names_and_paths.map { |np| np.keys[0] }
    tsv_string = col_names.join("\t") + "\n"

    study_manifest[:files].each do |file_info|
      file_row = col_names_and_paths.map do |name_and_path|
        path = name_and_path.values[0]
        file_value = file_info.dig(*(path.split('.')))
        file_value ? file_value : ""
      end
      tsv_string += (file_row.join("\t") + "\n")
    end
    if study_manifest[:directories].present?
      study_manifest[:directories].each do |directory_entry|
        directory_entry.each do |dir_file_info|
          file_row = col_names_and_paths.map do |name_and_path|
            path = name_and_path.values[0]
            file_value = dir_file_info.dig(*(path.split('.')))
            file_value ? file_value : ""
          end
          tsv_string += (file_row.join("\t") + "\n")
        end
      end
    end
    tsv_string
  end
end
