# collection of methods involved in parsing files
# also includes option return status object when being called from Api::V1::StudyFilesController
class FileParseService
  # * *params*
  #   - +study_file+      (StudyFile) => File being parsed
  #   - +study+           (Study) => Study to which StudyFile belongs
  #   - +user+            (User) => User initiating parse action (for email delivery)
  #   - +reparse+         (Boolean) => Control for deleting existing data when initiating parse (default: false)
  #   - +persist_on_fail+ (Boolean) => Control for persisting files from GCS buckets on parse fail (default: false)
  #
  # * *returns*
  #   - (Hash) => Status object with http status_code and optional error message
  def self.run_parse_job(study_file, study, user, reparse: false, persist_on_fail: false)
    logger = Rails.logger
    logger.info "#{Time.zone.now}: Parsing #{study_file.name} as #{study_file.file_type} in study #{study.name}"
    if !study_file.parseable?
      return {
          status_code: 422,
          error: "Files of type #{study_file.file_type} are not parseable"
      }
    elsif study_file.parsing?
      return {
          status_code: 405,
          error: "File: #{study_file.upload_file_name} is already parsing"
      }
    else
      self.create_bundle_from_file_options(study_file, study)
      case study_file.file_type
      when 'Cluster'
        job = IngestJob.new(study: study, study_file: study_file, user: user, action: :ingest_cluster, reparse: reparse,
                            persist_on_fail: persist_on_fail)
        job.delay.push_remote_and_launch_ingest
        # check if there is a coordinate label file waiting to be parsed
        # must reload study_file object as associations have possibly been updated
        study_file.reload
        if study_file.has_completed_bundle?
          study_file.bundled_files.each do |coordinate_file|
            # pre-emptively set parse_status to prevent initialize_coordinate_label_data_arrays from failing due to race condition
            study_file.update(parse_status: 'parsing')
            study.delay.initialize_coordinate_label_data_arrays(coordinate_file, user, {reparse: reparse})
          end
        end
      when 'Coordinate Labels'
        if study_file.has_completed_bundle?
          ParseUtils.delay.initialize_coordinate_label_data_arrays(study, study_file, user, {reparse: reparse})
        else
          return self.missing_bundled_file(study_file)
        end
      when 'Expression Matrix'
        job = IngestJob.new(study: study, study_file: study_file, user: user, action: :ingest_expression, reparse: reparse,
                            persist_on_fail: persist_on_fail)
        job.delay.push_remote_and_launch_ingest
      when 'MM Coordinate Matrix'
        study_file.reload
        if study_file.has_completed_bundle?
          study_file.bundled_files.update_all(parse_status: 'parsing')
          job = IngestJob.new(study: study, study_file: study_file, user: user, action: :ingest_expression, reparse: reparse,
                              persist_on_fail: persist_on_fail)
          job.delay.push_remote_and_launch_ingest
        else
          study.delay.send_to_firecloud(study_file)
          return self.missing_bundled_file(study_file)
        end
      when /10X/
        # push immediately to avoid race condition when initiating parse
        study.delay.send_to_firecloud(study_file) if study_file.is_local?
        study_file.reload
        if study_file.has_completed_bundle?
          bundle = study_file.study_file_bundle
          matrix = bundle.parent
          bundle.study_files.update_all(parse_status: 'parsing')
          job = IngestJob.new(study: study, study_file: matrix, user: user, action: :ingest_expression, reparse: reparse,
                              persist_on_fail: persist_on_fail)
          job.delay.push_remote_and_launch_ingest(skip_push: true)
        else
          return self.missing_bundled_file(study_file)
        end
      when 'Gene List'
        ParseUtils.delay.initialize_precomputed_scores(study, study_file, user)
      when 'Metadata'
        job = IngestJob.new(study: study, study_file: study_file, user: user, action: :ingest_cell_metadata, reparse: reparse,
                            persist_on_fail: persist_on_fail)
        job.delay.push_remote_and_launch_ingest
      when 'Analysis Output'
        case @study_file.options[:analysis_name]
        when 'infercnv'
          if @study_file.options[:visualization_name] == 'ideogram.js'
            ParseUtils.delay.extract_analysis_output_files(@study, current_user, @study_file, @study_file.options[:analysis_name])
          end
        else
          Rails.logger.info "Aborting parse of #{@study_file.name} as #{@study_file.file_type} in study #{@study.name}; not applicable"
        end
      end
      study_file.update(parse_status: 'parsing')
      changes = ["Study file added: #{study_file.upload_file_name}"]
      if study.study_shares.any?
        SingleCellMailer.share_update_notification(study, changes, user).deliver_now
      end
      return {
          status_code: 204
      }
    end
  end

  # helper for handling study file bundles when initiating parses
  def self.create_bundle_from_file_options(study_file, study)
    study_file_bundle = study_file.study_file_bundle
    if study_file_bundle.nil?
      StudyFileBundle::BUNDLE_REQUIREMENTS.each do |parent_type, bundled_types|
        options_key = StudyFileBundle::PARENT_FILE_OPTIONS_KEYNAMES[parent_type]
        if study_file.file_type == parent_type
          # check if any files have been staged for bundling - this can happen from the sync page by setting the
          # study_file.options[options_key] value with the parent file id
          bundled_files = StudyFile.where(:file_type.in => bundled_types, study_id: study.id,
                                          "options.#{options_key}" => study_file.id.to_s)
          if bundled_files.any?
            study_file_bundle = StudyFileBundle.initialize_from_parent(study, study_file)
            study_file_bundle.add_files(*bundled_files)
          end
        elsif bundled_types.include?(study_file.file_type)
          parent_file_id = study_file.options.with_indifferent_access[options_key]
          parent_file = StudyFile.find_by(id: parent_file_id)
          # parent file may or may not be present, so check first
          if parent_file.present?
            study_file_bundle = StudyFileBundle.initialize_from_parent(study, parent_file)
            study_file_bundle.add_files(study_file)
          end
        end
      end
    end
  end

  # Helper for rendering error when a bundled file is missing requirements for parsing
  def self.missing_bundled_file(study_file)
    Rails.logger.info "#{Time.zone.now}: Parse for #{study_file.name} as #{study_file.file_type} in study #{study_file.study.name} aborted; missing required files"
    {
        status_code: 412,
        error: "File is not parseable; missing required files for parsing #{study_file.file_type} file type: #{StudyFileBundle::PARSEABLE_BUNDLE_REQUIREMENTS.to_json}"
    }
  end

  # clean up any cached ingest pipeline run files older than 30 days
  def self.clean_up_ingest_artifacts
    cutoff_date = 30.days.ago
    Rails.logger.info "Cleaning up all ingest pipeline artifacts older than #{cutoff_date}"
    Study.where(queued_for_deletion: false, detached: false).each do |study|
      Rails.logger.info "Checking #{study.accession}:#{study.bucket_id}"
      study.delete_ingest_artifacts(cutoff_date)
    end
  end

  # clean up any cached study file copies that failed to ingest, including log files older than provided age limit
  def self.delete_ingest_artifacts(study, file_age_cutoff)
    begin
      # get all remote files under the 'parse_logs' folder
      remotes = ApplicationController.firecloud_client.execute_gcloud_method(:get_workspace_files, 0, study.bucket_id, prefix: 'parse_logs')
      remotes.each do |remote|
        creation_date = remote.created_at.in_time_zone
        if remote.size > 0 && creation_date < file_age_cutoff
          Rails.logger.info "Deleting #{remote.name} from #{study.bucket_id}"
          remote.delete
        end
      end
    rescue => e
      error_context = ErrorTracker.format_extra_context(study)
      ErrorTracker.report_exception(e, nil, error_context)
    end
  end
end
