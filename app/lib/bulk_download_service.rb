##
# BulkDownloadService: helper class for generating curl configuration files for initiating bulk downloads from
# keyword and faceted search

class BulkDownloadService

  extend ErrorTracker

  # Generate a String representation of a configuration file containing URLs and output paths to pass to
  # curl for initiating bulk downloads
  #
  # * *params*
  #   - +study_files+ (Array<StudyFile>) => Array of StudyFiles to be downloaded
  #   - +user+ (User) => User requesting download
  #   - +study_bucket_map+ => Map of study IDs to bucket names
  #   - +output_pathname_map+ => Map of study file IDs to output pathnames
  #
  # * *return*
  #   - (String) => String representation of signed URLs and output filepaths to pass to curl
  def self.generate_curl_configuration(study_files:, user:, study_bucket_map:, output_pathname_map:)
    curl_configs = ['--create-dirs', '--compressed']
    # Get signed URLs for all files in the requested download objects, and update user quota
    Parallel.map(study_files, in_threads: 100) do |study_file|
      client = FireCloudClient.new
      curl_configs << self.get_single_curl_command(file: study_file, fc_client: client, user: user,
                                                   study_bucket_map: study_bucket_map, output_pathname_map: output_pathname_map)
    end
    curl_configs.join("\n\n")
  end

  # Update a user's download quota after assembling the list of files requested
  # Since the download happens outside the purview of the portal, the quota impact is front-loaded
  #
  # * *params*
  #   - +user+ (User) => User performing bulk download action
  #   - +files+ (Array<StudyFile>) => Array of files requested
  #
  # * *raises*
  #   - (RuntimeError) => User download quota exceeded
  def self.update_user_download_quota(user:, files:)
    download_quota = ApplicationController.get_download_quota
    bytes_requested = files.map(&:upload_file_size).compact.reduce(:+)
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
  #   - (Array<String>) Array of permitted accessions to use in bulk download request
  def self.get_permitted_accessions(study_accessions:, user:)
    viewable_accessions = Study.viewable(user).pluck(:accession)
    permitted_accessions = study_accessions & viewable_accessions

    # collect array of study accession requiring acceptance of download agreement (checking for expiration)
    agreement_accessions = []
    DownloadAgreement.all.each do |agreement|
      agreement_accessions << agreement.study.accession unless agreement.expired?
    end
    requires_agreement = permitted_accessions & agreement_accessions
    if requires_agreement.any?
      user_lacks_acceptance = []
      requires_agreement.each do |accession|
        user_lacks_acceptance << accession unless DownloadAcceptance.where(study_accession: accession, email: user.email).exists?
      end
      permitted_accessions -= user_lacks_acceptance
    end
    permitted_accessions
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

  # Generate a String representation of a configuration file containing URLs and output paths to pass to
  # curl for initiating bulk downloads
  #
  # * *params*
  #   - +file+ (StudyFile) => StudyFiles to be downloaded
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
    file_location = file.bucket_location
    bucket_name = study_bucket_map[file.study_id.to_s]
    output_path = output_pathname_map[file.id.to_s]

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
  #
  # * *returns*
  #   - (Hash<String, String>) => Map of study file IDs to output pathnames
  def self.generate_output_path_map(study_files)
    output_map = {}
    study_files.each do |study_file|
      output_map[study_file.id.to_s] = study_file.bulk_download_pathname
    end
    output_map
  end
end
