# collection of methods to be called during sync actions
class StudySyncService
  # batch size for remote file processing
  # value is mostly used for messaging & tests when overridden
  BATCH_SIZE = 1000

  # mirror local permissions to that of the workspace
  #
  # * *params*
  #   - +study+ (Study) => study to update shares from associated workspace ACL
  #
  # * *yields*
  #   - (StudyShare) => new StudyShare records, as needed
  #
  # * *returns*
  #   - (Array<StudyShare>) => any updated StudyShare records
  def self.update_shares_from_acl(study)
    return [] unless study.terra_study

    study_ws = "#{study.firecloud_project}/#{study.firecloud_workspace}"
    Rails.logger.info "setting shares for #{study.accession} based on #{study_ws} acl"
    updated_permissions = []
    workspace_permissions = ApplicationController.firecloud_client.get_workspace_acl(study.firecloud_project,
                                                                                     study.firecloud_workspace)
    workspace_permissions['acl'].each do |user, permissions|
      share_from_acl = process_acl_entry(study, user, permissions)
      updated_permissions << share_from_acl if share_from_acl.present?
    end

    # now check to see if there have been permissions removed in Terra that need to be removed on the portal side
    new_study_permissions = study.study_shares.to_a
    new_study_permissions.each do |share|
      if workspace_permissions.dig('acl', share.email).nil?
        Rails.logger.info "removing #{share.email} access to #{study.accession} via sync - no longer in Terra acl"
        share.delete
      end
    end
    updated_permissions
  end

  # process an individual workspace ACL entry and create new study shares as needed
  #
  # * *params*
  #   - +study+ (Study) => study to update shares from associated workspace ACL
  #   - +acl_email+ (String) => email address of workspace ACL entry
  #   - +acl_permissions+ (Hash) => remote ACL object w/ user permissions
  #
  # * *returns*
  #   - (StudyShare, nil) => new/updated StudyShare record, as needed (or nil if no changes are required)
  def self.process_acl_entry(study, acl_email, acl_permissions)
    Rails.logger.info "processing permissions in #{study.accession} for #{acl_email}"
    readonly_client = ApplicationController.read_only_firecloud_client
    is_readonly_share = readonly_client.present? && acl_email == readonly_client.issuer
    return nil if acl_permissions['accessLevel'] =~ /OWNER/i || is_readonly_share

    portal_permissions = study.local_acl
    if !portal_permissions.key?(acl_email)
      new_share = study.study_shares.build(email: acl_email,
                                           permission: StudyShare::PORTAL_ACL_MAP[acl_permissions['accessLevel']],
                                           firecloud_project: study.firecloud_project,
                                           firecloud_workspace: study.firecloud_workspace)
      # skip validation as we don't wont to set the acl in Terra as it already exists
      new_share.save(validate: false)
      new_share
    elsif portal_permissions[acl_email] != StudyShare::PORTAL_ACL_MAP[acl_permissions['accessLevel']] &&
          acl_email != study.user.email
      # share exists, but permissions are wrong
      share = study.study_shares.detect { |s| s.email == acl_email }
      share.update(permission: StudyShare::PORTAL_ACL_MAP[acl_permissions['accessLevel']])
      share
    end
  end

  # main method to iterate list of remote files and create entries as needed
  #
  #
  # * *params*
  #   - +study+ (Study) => study to process remote files for
  #   - +token+ (String) => pointer to next page of files
  #
  # * *returns*
  #   - (Array<StudyFile>) => array of unsynced StudyFile documents
  def self.process_remotes(study, token: nil)
    Rails.logger.info "processing #{token || 'initial'} batch of remotes for #{study.accession}"
    workspace_files = get_file_batch(study, token:)
    file_extension_map = create_file_map(workspace_files.dup)
    submission_ids = get_submission_ids(study)
    process_file_batch(study, workspace_files, submission_ids, file_extension_map:)
  end

  # get batch of files from workspace bucket as defined by BATCH_SIZE + 1
  # can also paginate more files using page token
  #
  # * *params*
  #   - +study+ (Study) => study to process remote files for
  #   - +token+ (String) => pointer to next page of files
  #   - +batch_size+ (Integer) => amount of files to retrieve, defaulting to BATCH_SIZE
  #
  # * *returns*
  #   - (Google::Cloud::Storage::File::List)
  def self.get_file_batch(study, token: nil, batch_size: BATCH_SIZE)
    study.storage_provider.get_study_bucket_files(
      study.bucket_id, delimiter: '_scp_internal', token:, max: batch_size
    )
  end

  # determine amount of remaining remote objects to process in study bucket
  #
  # * *params*
  #   - +study+ (Study) => study to process remote files for
  #   - +token+ (String) => pointer to next page of files
  #
  # * *returns*
  #   - (Integer)
  def self.count_remaining_files(study, token: nil)
    batch = get_file_batch(study, token:)
    batch.all.count
  end

  # process a block of files from bucket
  # will ignore submission outputs, files in _scp_internal or parse_logs
  # will also add files to DirectoryListing objects as needed
  #
  # * *params*
  #   - +study+ (Study) => study to create new entities in
  #   - +files+ (Google::Cloud::Storage::File::List) => current batch of remote files in GCP bucket (up to 1K)
  #   - +submission_ids+ (Array<String>) => array of submission UUIDs to ignore files in
  #   - +file_extension_map+ (Hash) => output from StudySyncService,create_file_map
  #
  # * *returns*
  #   - (Array<StudyFile>) => array of unsynced StudyFile documents from batch
  def self.process_file_batch(study, files, submission_ids, file_extension_map:)
    response = { page_token: files.token, unsynced_study_files: [], remaining_files: 0 }
    valid_files = remove_submission_outputs(files, submission_ids)
    new_files = remove_synced_files(study, valid_files)
    dir_files = find_files_for_directories(new_files, file_extension_map, study)
    add_files_to_directories(study, dir_files)
    unsynced_files_in_batch = remove_directory_files(dir_files, new_files)
    Rails.logger.info "found #{unsynced_files_in_batch.count} remotes in batch to process for #{study.accession}"
    unsynced_files_in_batch.each do |file|
      next if file.size == 0

      unsynced_file = StudyFile.new(study_id: study.id, name: file.name, upload_file_name: file.name,
                                    upload_content_type: file.content_type, upload_file_size: file.size,
                                    generation: file.generation, remote_location: file.name)
      unsynced_file.build_expression_file_info
      response[:unsynced_study_files] << unsynced_file
    end
    if files.next?
      response[:remaining_files] = count_remaining_files(study, token: files.token)
    end
    response
  end

  # create a map of remote paths to counts of files by extension
  # used in creating DirectoryListing objects via sync
  #
  # * *params*
  #   - +files+ (Google::Cloud::Storage::File::List) => listing of remote files in GCP bucket
  #
  # * *returns*
  #   - (Hash) => map of remote directories and counts of files, by extension
  def self.create_file_map(files)
    DirectoryListing.create_extension_map(files, {})
  end

  # detect candidate files for DirectoryListing entries
  #
  # * *params*
  #   - +files+ (Google::Cloud::Storage::File::List) => current batch of remote files in GCP bucket (up to 1K)
  #   - +file_extension_map+ (Hash) => output from StudySyncService,create_file_map
  #   - +study+ (Study) => study to create/update DirectoryListings in
  #
  # * *returns*
  #   - (Array<StudyFile>) => array of remote files to add to DirectoryListings
  def self.find_files_for_directories(files, file_extension_map, study)
    files.select do |file|
      file_type = DirectoryListing.file_type_from_extension(file.name)
      directory_name = DirectoryListing.get_folder_name(file.name)
      file_extension_map.dig(directory_name, file_type).to_i >= DirectoryListing::MIN_SIZE && directory_name != '/' ||
        (directory_name == '/' && DirectoryListing::PRIMARY_DATA_TYPES.include?(file_type)) ||
        DirectoryListing.where(name: directory_name, file_type:, study:).exists? # gotcha for partial results
    end
  end

  # add a batch of files to corresponding DirectoryListing entries
  #
  # * *params*
  #   - +study+ (Study) => study to create/update DirectoryListings in
  #   - +files+ (Google::Cloud::Storage::File::List) => list of candidate remote files
  #
  # * *yields*
  #   - (DirctoryListing) => new/updated DirectoryListing objects to by synced
  def self.add_files_to_directories(study, files)
    files.each do |file|
      file_type = DirectoryListing.file_type_from_extension(file.name)
      directory_name = DirectoryListing.get_folder_name(file.name)
      remote = { 'name' => file.name, 'size' => file.size, 'generation' => file.generation.to_s }
      existing_dir = DirectoryListing.find_by(study_id: study.id, name: directory_name, file_type:)
      if existing_dir.nil?
        study.directory_listings.create(name: directory_name, file_type:, files: [remote], sync_status: false)
      elsif existing_dir.files.detect { |f| f['generation'].to_s == file.generation.to_s }.nil?
        existing_dir.files << remote
        existing_dir.sync_status = false
        existing_dir.save
      end
    end
  end

  # load all unsynced DirectoryListing entries and partition into 2 groups - primary data, and other
  #
  # * *params*
  #   - +study+ (Study) => study to partition DirectoryListing objects in
  #
  # * *returns*
  #   - (Array<DirectoryListing>) => two arrays of DirectoryListings (primary data, other)
  def self.load_unsynced_directories(study)
    study.reload # ensure latest state
    directories = study.directory_listings.unsynced
    directories.partition { |dir| DirectoryListing::PRIMARY_DATA_TYPES.include?(dir.file_type) }
  end

  # set an object of available files for sync views
  #
  # * *params*
  #   - +files+ (Array<Google::Cloud::Storage::File>) => array of remote GCS files that are unsynced
  #
  # * *returns*
  #   - (Array<Hash>) => array of objects with filename, generation, and file size
  def self.set_available_files(files)
    files.map { |f| { name: f.name, generation: f.generation, size: f.upload_file_size } }
  end

  # set array of known "synced" study files for use in sync views
  # will remove any bundled child files as these are rendered dynamically from parent file
  #
  # * *params*
  #   - +study+ (Study) => study to create/update DirectoryListings in
  #   - +orphaned_files+ (Array<StudyFile>) => all study files where remote file is now missing
  #
  # * *returns*
  #   - (Array<StudyFile>) => array of study files that are in "synced" state
  def self.set_synced_files(study, orphaned_files)
    study.reload
    synced_files = study.study_files.valid - orphaned_files
    bundled_file_ids = study.study_file_bundles.map { |bundle| bundle.bundled_files.to_a.map(&:id) }.flatten
    synced_files.delete_if { |file| bundled_file_ids.include?(file.id) }
  end

  # retrieve all Terra workspace submission ids to use in filtering bucket files
  #
  # * *params*
  #   - +study+ (Study) => study to get submissions in
  #
  # * *returns*
  #   - (Array<String>) => array of submission UUIDs
  def self.get_submission_ids(study)
    ApplicationController.firecloud_client.get_workspace_submissions(
      study.firecloud_project, study.firecloud_workspace
    ).map { |s| s['submissionId'] }
  end

  # remove files from batch that are submission outputs from a Terra workflow
  #
  # * *params*
  #   - +files+ (Array<Google::Cloud::Storage::File>) => current batch of remote files in GCP bucket (up to 1K)
  #   - +submission_ids+ (Array<String>) => array of submission UUIDs to ignore files in
  #
  # * *returns*
  #   - (Array<Google::Cloud::Storage::File>) => filtered list of remote files
  def self.remove_submission_outputs(files, submission_ids)
    submission_outputs = files.select { |f| submission_ids.include?(f.name.split('/').first) }.map(&:generation)
    files.delete_if { |f| submission_outputs.include?(f.generation) }
  end

  # remove known files from remote list
  # also ignores files in 'parse_logs' directory
  # TODO: SCP-4595 - move 'parse_logs' into '_scp_internal' so this is done automatically
  #
  # * *params*
  #   - +study+ (Study) => study to get list of valid StudyFile entries from
  #   - +files+ (Array<Google::Cloud::Storage::File>) => current batch of remote files in GCP bucket (up to 1K)
  #
  # * *returns*
  #   - (Array<Google::Cloud::Storage::File>) => filtered list of remote files
  def self.remove_synced_files(study, files)
    files_to_remove = files.select do |file|
      study.study_files.valid.detect { |f| f.generation.to_s == file.generation.to_s }
    end.map { |f| f.generation.to_s }
    files.delete_if { |f| files_to_remove.include?(f.generation.to_s) || f.name.start_with?('parse_logs') }
  end

  # remove files that have been added to directory listings from list to process
  #
  # * *params*
  #   - +dir_files+ (Array<Google::Cloud::Storage::File>) => list of files already added to a DirectoryListing
  #   - +workspace_files+ (Array<Google::Cloud::Storage::File>) => current batch of remote files in GCP bucket (up to 1K)
  #
  # * *returns*
  #   - (Array<Google::Cloud::Storage::File>) => filtered list of remote files
  def self.remove_directory_files(dir_files, workspace_files)
    generations = dir_files.map(&:generation)
    workspace_files.delete_if { |f| generations.include?(f.generation) }
  end

  # find StudyFile entries where remote file has been removed from bucket
  #
  # * *params*
  #   - +study+ (Study) => study to get list of valid StudyFile entries from
  #
  # * *returns*
  #   - (Array<StudyFile) => array of StudyFile entries where remote file is missing
  def self.find_orphaned_files(study)
    storage_provider = study.storage_provider
    study.study_files.valid.reject do |study_file|
      storage_provider.bucket_file_exists?(study.bucket_id, study_file.bucket_location)
    end
  end

  # handle setting the content metadata headers (Content-Type, Content-Encoding) for a GCS resource (e.g. file)
  # this is used mainly to address issues when a user has directly uploaded a file to a bucket via gcloud CLI which can
  # result in headers are not being set correctly that causes downstream issues when localizing files for parsing
  #
  # * *params*
  #   - +study_file+ (StudyFile) => recently synced StudyFile
  #
  # * *returns*
  #  - (Boolean) => T/F on whether headers were changed
  def self.fix_file_content_headers(study_file)
    return false unless study_file.is_a?(StudyFile) && study_file.study.present? && study_file.parseable?

    study = study_file.study
    file = study.storage_provider.get_study_bucket_file(study.bucket_id, study_file.bucket_location)
    return false unless gzipped?(file) && study_file.remote_location.present? # skip uncompressed & SCP UI uploaded files

    # at this point, we know the file is gzipped, and was not uploaded through the SCP UI
    # set content_type to application/gzip and ensure there is no content_encoding header
    # this mimics what happens when a user uploads a gzipped file through either the SCP or GCS UI
    Rails.logger.info "correcting headers on synced file #{file.name} (#{file.content_type}) in #{file.bucket}"
    file.update do |f|
      f.content_type = 'application/gzip'
      f.content_encoding = ''
    end

    Rails.logger.info "headers updated on #{file.name} to content_type: #{file.content_type}, " \
                      "content_encoding: #{file.content_encoding}"
    true
  end

  # tell if a file has been gzipped
  #
  # * *params*
  #   - +file+ (Google::Cloud::Storage::File) => remote GCS file in workspace bucket
  #
  # * *returns*
  #  - (Boolean)
  def self.gzipped?(file)
    if file.name&.end_with?('.gz') || file.content_type == 'application/gzip'
      return true
    end

    # read first two bytes into memory and check against StudyFile::GZIP_MAGIC_NUMBER
    begin
      first_two_bytes = file.download(range: 0..1, skip_decompress: true)
      first_two_bytes.rewind
      first_two_bytes.read == StudyFile::GZIP_MAGIC_NUMBER
    rescue StandardError => e
      Rails.logger.error "error checking gzip status on #{file.name}"
      ErrorTracker.report_exception(e, nil, file)
      false # we don't really know, so return false to halt execution
    end
  end
end
