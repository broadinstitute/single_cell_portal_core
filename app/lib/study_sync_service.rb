# study_sync_service.rb
# helper class containing sync-related methods for discovering files, managing directories, and updating
# workspace ACLs

class StudySyncService

  # match filenames that start with a . or have a /. in their path
  HIDDEN_FILE_REGEX = /\/\.|^\./

  # iterate through list of GCP bucket files and build up necessary sync list objects
  def self.process_workspace_bucket_files(study, files, files_by_directory:, file_extension_map:,
                                          unsynced_files:, submission_ids:)
    # first mark any files that we already know are study files that haven't changed (can tell by generation tag)
    files_to_remove = []
    files.each do |file|
      # first, check if file is in a submission directory, and if so mark it for removal from list of files to sync
      # also ignore any files in the parse_logs folder
      base_dir = file.name.split('/').first
      if submission_ids.include?(base_dir) || base_dir == 'parse_logs' || file.name.end_with?('/')
        files_to_remove << file.generation
      else
        directory_name = DirectoryListing.get_folder_name(file.name)
        found_file = {'name' => file.name, 'size' => file.size, 'generation' => file.generation}
        # don't add directories to files_by_dir
        unless file.name.end_with?('/')
          # add to list of discovered files
          files_by_directory[directory_name] ||= []
          files_by_directory[directory_name] << found_file
        end
        found_study_file = study_files.detect {|f| f.generation.to_i == file.generation }
        if found_study_file
          synced_study_files << found_study_file
          files_to_remove << file.generation
        end
      end
    end

    # remove files from list to process
    files.delete_if {|f| files_to_remove.include?(f.generation)}

    # next update map of existing files to determine what can be grouped together in a directory listing
    file_extension_map = DirectoryListing.create_extension_map(files, file_extension_map)

    files.each do |file|
      # check first if file type is in file map in a group larger than 10 (or 20 for text files)
      file_extension = DirectoryListing.file_extension(file.name)
      directory_name = DirectoryListing.get_folder_name(file.name)
      if file_extension_map.has_key?(directory_name) && !file_extension_map[directory_name][file_extension].nil? &&
        file_extension_map[directory_name][file_extension] >= DirectoryListing::MIN_SIZE
        self.process_directory_listing_file(file, file_extension)
      else
        # we are now dealing with singleton files or fastqs, so process accordingly (making sure to ignore directories)
        if DirectoryListing::PRIMARY_DATA_TYPES.any? {|ext| file_extension.include?(ext)} && !file.name.end_with?('/')
          # process fastq file into appropriate directory listing
          self.process_directory_listing_file(file, 'fastq')
        else
          # make sure file is not actually a folder by checking its size
          if file.size > 0
            # create a new entry
            unsynced_file = StudyFile.new(study_id: @study.id, name: file.name, upload_file_name: file.name,
                                          upload_content_type: file.content_type, upload_file_size: file.size,
                                          generation: file.generation, remote_location: file.name)
            unsynced_file.build_expression_file_info
            unsynced_files << unsynced_file
          end
        end
      end
    end
  end

  def self.find_existing_files(study, bucket_files, submission_ids)
    # first mark any files that we already know are study files that haven't changed (can tell by generation tag)
    files_to_remove = []
    bucket_files.each do |file|
      # first, check if file is in a submission directory, and if so mark it for removal from list of files to sync
      # also ignore any files in the parse_logs folder
      base_dir = file.name.split('/').first
      if submission_ids.include?(base_dir) || base_dir == 'parse_logs' || file.name.end_with?('/')
        files_to_remove << file.generation
      else
        directory_name = DirectoryListing.get_folder_name(file.name)
        found_file = {'name' => file.name, 'size' => file.size, 'generation' => file.generation}
        # don't add directories to files_by_dir
        unless file.name.end_with?('/')
          # add to list of discovered files
          files_by_directory[directory_name] ||= []
          files_by_directory[directory_name] << found_file
        end
        found_study_file = study_files.detect {|f| f.generation.to_i == file.generation }
        if found_study_file
          synced_study_files << found_study_file
          files_to_remove << file.generation
        end
      end
    end
  end

  # helper to process a file into a directory listing object
  def self.process_directory_listing_file(study, file, file_type, directories)
    directory = DirectoryListing.get_folder_name(file.name)
    all_dirs = @directories + @unsynced_directories
    existing_dir = all_dirs.detect {|d| d.name == directory && d.file_type == file_type}
    found_file = {'name' => file.name, 'size' => file.size, 'generation' => file.generation}
    if existing_dir.nil?
      dir = @study.directory_listings.build(name: directory, file_type: file_type, files: [found_file], sync_status: false)
      @unsynced_directories << dir
    elsif existing_dir.files.detect {|f| f['generation'].to_i == file.generation.to_i }.nil?
      existing_dir.files << found_file
      existing_dir.sync_status = false
      if @unsynced_directories.map(&:name).include?(existing_dir.name)
        @unsynced_directories.delete(existing_dir)
      end
      @unsynced_directories << existing_dir
    end
  end

  def self.process_workflow_output(study, output_name, file_url, remote_gs_file, workflow, submission_id, submission_config)
    path_parts = file_url.split('/')
    basename = path_parts.last
    new_location = "outputs_#{study.id}_#{submission_id}/#{basename}"
    # check if file has already been synced first
    # we can only do this by md5 hash as the filename and generation will be different
    existing_file = ApplicationController.firecloud_client.execute_gcloud_method(:get_workspace_file, 0, @study.bucket_id, new_location)
    unless existing_file.present? && existing_file.md5 == remote_gs_file.md5 && StudyFile.where(study_id: study.id, upload_file_name: new_location).exists?
      # now copy the file to a new location for syncing, marking as default type of 'Analysis Output'
      new_file = remote_gs_file.copy new_location
      unsynced_output = StudyFile.new(study_id: @study.id, name: new_file.name, upload_file_name: new_file.name,
                                      upload_content_type: new_file.content_type, upload_file_size: new_file.size,
                                      generation: new_file.generation, remote_location: new_file.name,
                                      options: {submission_id: submission_id})
      unsynced_output.build_expression_file_info
      # process output according to analysis_configuration output parameters and associations (if present)
      workflow_parts = output_name.split('.')
      call_name = workflow_parts.shift
      param_name = workflow_parts.join('.')
      if @special_sync # only process outputs from 'registered' analyses
        Rails.logger.info "Processing output #{output_name}:#{file_url} in #{submission_id}/#{workflow['workflowId']}"
        # find matching output analysis_parameter
        output_param = @analysis_configuration.analysis_parameters.outputs.detect {|param| param.parameter_name == param_name && param.call_name == call_name}
        # set declared file type
        unsynced_output.file_type = output_param.output_file_type
        # process any direct attribute assignments or associations
        output_param.analysis_output_associations.each do |association|
          unsynced_output = association.process_output_file(unsynced_output, submission_config, @study)
        end
      end
      @unsynced_files << unsynced_output
    end
  end


  def self.visible_unsynced_files(unsynced_files)
    unsynced_files.select { |f| HIDDEN_FILE_REGEX.match(f.upload_file_name).nil? }
  end

  def self.hidden_unsynced_files(unsynced_files)
    unsynced_files.select { |f| HIDDEN_FILE_REGEX.match(f.upload_file_name).present? }
  end

  # update all shares for a study based off of the Terra workspace ACL
  # will create new shares, update/remove existing entries as needed
  #
  # * *params*
  #   - +study+ (Study) => study to update shares in
  #
  # * *returns*
  #   - (Array<StudyShare>) => Array of updated StudyShare entries
  def self.update_study_shares_from_workspace(study)
    changed_permissions = []
    portal_permissions = study.local_acl
    firecloud_permissions = ApplicationController.firecloud_client.get_workspace_acl(study.firecloud_project, study.firecloud_workspace)
    firecloud_permissions['acl'].each do |user, permissions|
      # skip project owner permissions, they aren't relevant in this context
      # also skip the readonly service account
      if permissions['accessLevel'] =~ /OWNER/i || (ApplicationController.read_only_firecloud_client.present? && user == ApplicationController.read_only_firecloud_client.issuer)
        next
      else
        # determine whether permissions are incorrect or missing completely
        if !portal_permissions.has_key?(user)
          new_share = study.study_shares.build(email: user,
                                                permission: StudyShare::PORTAL_ACL_MAP[permissions['accessLevel']],
                                                firecloud_project: study.firecloud_project,
                                                firecloud_workspace: study.firecloud_workspace,

                                                )
          # skip validation as we don't wont to set the acl in FireCloud as it already exists
          new_share.save(validate: false)
          changed_permissions << new_share
        elsif portal_permissions[user] != StudyShare::PORTAL_ACL_MAP[permissions['accessLevel']] && user != study.user.email
          # share exists, but permissions are wrong
          share = study.study_shares.detect {|s| s.email == user}
          share.update(permission: StudyShare::PORTAL_ACL_MAP[permissions['accessLevel']])
          changed_permissions << share
        else
          # permissions are correct, skip
          next
        end
      end
    end

    # now check to see if there have been permissions removed in FireCloud that need to be removed on the portal side
    new_study_permissions = study.study_shares.to_a
    new_study_permissions.each do |share|
      if firecloud_permissions['acl'][share.email].nil?
        Rails.logger.info "Removing #{share.email} access to #{study.name} via sync - no longer in FireCloud acl"
        share.delete
      end
    end
    changed_permissions
  end
end
