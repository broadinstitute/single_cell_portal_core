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
  #   - +azul_files+ => Hash of Azul file summary objects
  #   - +context+ => Context of bulk download request ("study" for single-study, or "global" for search across all studies)
  #
  # * *return*
  #   - (String) => String representation of signed URLs and output filepaths to pass to curl
  def self.generate_curl_configuration(study_files:,
                                       directory_files: [],
                                       user:,
                                       study_bucket_map:,
                                       output_pathname_map:,
                                       azul_files: nil,
                                       context: 'study',
                                       os: '')
    curl_configs = %w(--create-dirs)
    curl_configs << '--compressed' unless os =~ /Win/ # most Windows installations of curl do not support --compressed
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
      output_path = RequestUtils.format_path_for_os(
        "output=\"#{study.accession}/file_supplemental_info.tsv\"", os
      )
      manifest_config += output_path
      curl_configs << manifest_config
    end
    azul_studies = azul_files ? azul_files.keys : []
    azul_file_configs = []
    azul_sequence_files = 0
    azul_analysis_files = 0

    if azul_files.present?
      hca_client = ApplicationController.hca_azul_client
      azul_file_configs = []
      azul_files.map do |shortname, file_infos|
        next if file_infos.empty?

        # pull out project manifest and process separately
        manifests, files = file_infos.partition { |f| f['file_type'] == 'Project Manifest' }
        manifest_info = manifests.first

        # only generate manifest link if user has requested it
        if manifest_info.present?
          manifest = hca_client.project_manifest_link(manifest_info['project_id'])
          # add location directive to allow following 302 redirect to manifest location
          manifest_output_path = RequestUtils.format_path_for_os(
            "output=\"#{shortname}/#{manifest_info['name']}\"", os
          )
          manifest_config = "--location\nurl=\"#{manifest['Location']}\"\n#{manifest_output_path}"
          azul_file_configs << manifest_config
        end

        # now process remainder of analysis/sequence files for download
        # each file_info hash will contain project IDs and file_types that can be used in a single query to Azul
        # to get all matching files
        # if no other files, skip to next project
        next if files.empty?

        project_id = files.first['project_id'] # project_id is same for all entries in this block
        file_query = { 'projectId' => { 'is' => [project_id] } }
        files.each do |file_info|
          file_query['fileFormat'] ||= { 'is' => [] }
          file_query['fileFormat']['is'] << file_info['file_format']
          case file_info['file_type']
          when 'analysis_file'
            azul_analysis_files += file_info['count']
          when 'sequence_file'
            azul_sequence_files += file_info['count']
          end
        end
        requested_files = hca_client.files(query: file_query)
        requested_files.each do |file_entry|
          file_output_path = RequestUtils.format_path_for_os(
            "#{shortname}/#{file_entry['name']}", os
          )
          file_config = "--location\nurl=\"#{file_entry['url']}\"\noutput=\"#{file_output_path}\""
          azul_file_configs << file_config
        end
      end
      curl_configs.concat(azul_file_configs)
    end
    file_map = create_file_type_map(study_files)
    MetricsService.log('file-download:curl-config', {
      numFiles: study_files.count,
      numMetadataFiles: file_map['Metadata'],
      numExpressionFiles: file_map['Expression Matrix'] + file_map['MM Coordinate Matrix'],
      numClusterFiles: file_map['Cluster'],
      numStudies: studies.count,
      studyAccessions: studies.map(&:accession),
      numAzulStudies: azul_studies.count,
      azulAccessions: azul_studies,
      numAzulFiles: azul_file_configs.count,
      numAzulAnalysisFiles: azul_analysis_files,
      numAzulSequenceFiles: azul_sequence_files,
      context: context,
      os: os
    }, user)
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
    file_bytes_requested = get_requested_bytes(files)
    dir_bytes_requested = get_requested_bytes(directories, size_method: :total_bytes)
    bytes_requested = file_bytes_requested + dir_bytes_requested
    if DownloadQuotaService.download_exceeds_quota?(user, bytes_requested)
      raise "Total file size exceeds user download quota: #{bytes_requested} bytes requested, #{bytes_allowed} bytes " \
            "allowed.  #{DownloadQuotaService::QUOTA_HELP_EMAIL}"
    else
      Rails.logger.info "Adding #{bytes_requested} bytes to user: #{user.id} download quota for bulk download"
      DownloadQuotaService.increment_user_quota(user, bytes_requested)
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
      # we may have orphaned download agreements, so ensure this is nil-safed
      agreement_accessions << agreement.study&.accession unless agreement.expired? || !agreement.study
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

    # ignore detached studies
    studies = Study.where(:accession.in => study_accessions, detached: false)
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
  # Will ignore detached studies by default to avoid errors trying to download from missing buckets
  #
  # * *params*
  #   - +study_accessions+ (Array<String>) => Array of StudyAccession values from which to pull files
  # * *return*
  #   - (Hash) => Array of study objects, each one containing a study_files array with name, type, and upload_file_size
  def self.get_download_info(study_accessions)
    studies = Study.where(:accession.in => study_accessions, detached: false)
    studies.map { |study| BulkDownloadService.study_download_info(study) }
  end

  # Get download preview information for a single study
  #
  # * *params*
  #   -+study+ (Study) => The study to retrieve download preview information for
  #
  # * *returns*
  #   - (Hash) => Hash of download information about the study, including an array of the study files
  def self.study_download_info(study)
    {
      name: study.name,
      accession: study.accession,
      description: study.description,
      study_source: 'SCP',
      study_files: study.study_files.map { |study_file| BulkDownloadService.study_file_download_info(study_file) }
    }
  end

  # Get download preview information for a single StudyFile
  #
  # * *params*
  #   - +study_file+ (StudyFile) => The study to retrieve download preview information for
  #
  # * *returns*
  #   - (Hash) => Hash of download information about the study file, including type and size
  def self.study_file_download_info(study_file)
    study_file_obj = {
      name: study_file.name,
      id: study_file.id.to_s,
      file_type: study_file.file_type,
      upload_file_size: study_file.upload_file_size,
    }
    if study_file.is_bundle_parent?
      study_file_obj[:bundled_files] = study_file.bundled_files.map { |sf| study_file_download_info(sf) }
    end
    study_file_obj
  end

  # get a tally of total bytes for a list of StudyFile or DirectoryListing objects
  #
  # * *params*
  #   - +study_files+ (Array<StudyFile>, Array(DirectoryListing), Mongoid::Criteria) => List of objects
  #   - +size_method+ (Symbol) => method to call to get size of object in bytes
  #
  # * *returns*
  #   - (Integer) => amount of total bytes counted against user download quota
  def self.get_requested_bytes(entries, size_method: :upload_file_size)
    entries.map(&size_method).compact.reduce(0, :+)
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
      ErrorTracker.report_exception(e, user, file, { storage_bucket: bucket_name})
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
  #   - +os+ (String) => name of client operating system (for determining / vs \)
  #
  # * *returns*
  #   - (Hash<String, String>) => Map of study file IDs to output pathnames
  def self.generate_output_path_map(study_files, directories=[], os: '')
    output_map = {}
    study_files.each do |study_file|
      output_map[study_file.id.to_s] = study_file.bulk_download_pathname(os: os)
    end
    directories.each do |directory|
      directory.files.each do |file|
        output_map[file[:name]] = directory.bulk_download_pathname(file, os: os)
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

  # create a map of study file types to counts of each type for reporting metrics
  def self.create_file_type_map(files)
    file_types = StudyFile::STUDY_FILE_TYPES
    # counts of file types are returned from iterating over list of all types and calling :select, :count
    # Hash[] initializes a new Hash from an nested array of two-element arrays, which are created from Array.zip
    # e.g. Hash[[:foo, :bar].zip([1,2])] => {foo: 1, bar: 2}
    Hash[file_types.zip(file_types.map { |type| files.select { |file| file.file_type == type }.count })]
  end
end
