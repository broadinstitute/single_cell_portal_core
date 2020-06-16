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
  #
  # * *return*
  #   - (String) => String representation of signed URLs and output filepaths to pass to curl
  def self.generate_curl_configuration(study_files:, user:)
    curl_configs = ['--create-dirs', '--compressed']
    # Get signed URLs for all files in the requested download objects, and update user quota
    Parallel.map(study_files, in_threads: 100) do |study_file|
      client = FireCloudClient.new
      curl_configs << self.get_single_curl_command(file: study_file, fc_client: client, user: user)
      # send along any bundled files along with the parent
      if study_file.is_bundle_parent?
        study_file.bundled_files.each do |bundled_file|
          curl_configs << self.get_single_curl_command(file: bundled_file, fc_client: client, user: user)
        end
      end
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
    bytes_requested = files.map(&:upload_file_size).reduce(:+)
    bytes_allowed = download_quota - user.daily_download_quota
    if bytes_requested > bytes_allowed
      raise RuntimeError.new "Total file size exceeds user download quota: #{bytes_requested} bytes requested, #{bytes_allowed} bytes allowed"
    else
      Rails.logger.info "Adding #{bytes_requested} bytes to user: #{user.id} download quota for bulk download"
      user.daily_download_quota += bytes_requested
      user.save
    end
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
    if file_types.include?('Expression')
      file_types.delete_if {|file_type| file_type == 'Expression'}
      file_types += ['Expression Matrix', 'MM Coordinate Matrix']
    end

    # get requested files
    studies = Study.where(:accession.in => study_accessions)
    if file_types.present?
      return studies.map {
          |study| study.study_files.by_type(file_types)
      }.flatten
    else
      return studies.map(&:study_files).flatten
    end
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
      files_by_type[req_type] = {total_files: files.size, total_bytes: files.map(&:upload_file_size).reduce(:+)}
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
  #
  # * *return*
  #   - (String) => String representation of single signed URL and output filepath to pass to curl
  def self.get_single_curl_command(file:, fc_client:, user:)
    fc_client ||= Study.firecloud_client
    # if a file is a StudyFile, use bucket_location, otherwise the :name key will contain its location (if DirectoryListing)
    file_location = file.bucket_location
    study = file.study
    output_path = file.bulk_download_pathname

    begin
      signed_url = fc_client.execute_gcloud_method(:generate_signed_url, 0, study.bucket_id, file_location,
                                                   expires: 1.day.to_i) # 1 day in seconds, 86400
      curl_config = [
          'url="' + signed_url + '"',
          'output="' + output_path + '"'
      ]
    rescue => e
      error_context = ErrorTracker.format_extra_context(study, file)
      ErrorTracker.report_exception(e, user, error_context)
      Rails.logger.error "Error generating signed url for #{output_path}; #{e.message}"
      curl_config = [
          '# Error downloading ' + output_path + '.  ' +
              'Did you delete the file in the bucket and not sync it in Single Cell Portal?'
      ]
    end
    curl_config.join("\n")
  end
end
