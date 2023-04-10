##
#
# UploadCleanupJob - a scheduled job that will verify that a study_file has successfully been uploaded to GCS and will then
# remove the local copy of the file
#
##

class UploadCleanupJob < Struct.new(:study, :study_file, :retry_count)

  MAX_RETRIES = 2

  def perform
    attempt = self.retry_count + 1
    Rails.logger.info "Loading UploadCleanupJob for #{study_file.upload_file_name}:#{study_file.id}, attempt #{attempt}"
    # make sure file or study isn't queued for deletion first
    if study_file.nil?
      Rails.logger.info "aborting UploadCleanupJob due to StudyFile already being deleted."
    elsif study_file.queued_for_deletion || study.queued_for_deletion
      Rails.logger.info "aborting UploadCleanupJob for #{study_file.bucket_location}:#{study_file.id} in '#{study.accession}', file queued for deletion"
      # check if there's still a local copy we need to clean up
      if study_file.is_local?
        study_file.remove_local_copy
      end
    else
      if !study_file.is_local?
        Rails.logger.error "error in UploadCleanupJob for #{study.accession}:#{study_file.bucket_location}:#{study_file.id}; file no longer present"
        SingleCellMailer.admin_notification('File missing on cleanup', nil, "<p>The study file #{study_file.upload_file_name} was missing from the local file system at the time of cleanup job execution.  Please check #{study.firecloud_project}/#{study.firecloud_workspace} to ensure the upload occurred.</p>")
      else
        begin
          # check workspace bucket for existence of remote file
          Rails.logger.info "performing UploadCleanupJob for #{study_file.bucket_location}:#{study_file.id} in '#{study.accession}', attempt ##{attempt}"
          remote_file = ApplicationController.firecloud_client.execute_gcloud_method(:get_workspace_file, 0, study.bucket_id, study_file.bucket_location)
          if remote_file.present?
            # check generation tags to make sure we're in sync
            Rails.logger.info "remote file located for #{study_file.bucket_location}:#{study_file.id}, checking generation tag"
            if remote_file.generation.to_s == study_file.generation
              Rails.logger.info "generation tags for #{study_file.bucket_location}:#{study_file.id} match, performing cleanup"
            else
              Rails.logger.info "generation tags for #{study_file.bucket_location}:#{study_file.id} do not match, updating database records"
              study_file.update(generation: remote_file.generation)
              Rails.logger.info "generation tag for #{study_file.bucket_location}:#{study_file.id} updated, performing cleanup"
            end
            # once everything is in sync, perform cleanup
            study_file.remove_local_copy
            Rails.logger.info "cleanup for #{study_file.bucket_location}:#{study_file.id} complete"
          else
            # remote file was not found, so schedule a new cleanup job to check again
            # file may be pushing in another thread, and attempting to push here creates infinite recursion if errors are encountered
            if attempt <= MAX_RETRIES
              interval = attempt * 2
              run_at = interval.minutes.from_now
              Rails.logger.info "remote file MISSING for #{study_file.bucket_location}:#{study_file.id}, scheduling new UploadCleanupJob for #{run_at}, attempt: #{attempt}"
              Delayed::Job.enqueue(UploadCleanupJob.new(study, study_file, attempt), run_at: run_at)
            else
              Rails.logger.error "file #{study.accession}:#{study_file.bucket_location}:#{study_file.id} has failed to push to #{study.bucket_id}"
              message = "<p>#{study_file.bucket_location} in #{study.accession} has failed to push to the associated bucket: #{study.bucket_id}</p>"
              message += "<p>This file is located in the #{Rails.env} environment at #{study_file.local_location}</p>"
              SingleCellMailer.admin_notification('UploadCleanupJob failure', nil, message).deliver_now
            end
          end
        rescue => e
          if attempt <= MAX_RETRIES
            interval = attempt * 2
            run_at = interval.minutes.from_now
            Rails.logger.error "error in UploadCleanupJob for #{study.accession}:#{study_file.bucket_location}:#{study_file.id}, will retry at #{run_at}; #{e.message}"
            Delayed::Job.enqueue(UploadCleanupJob.new(study, study_file, attempt), run_at: run_at)
          else
            ErrorTracker.report_exception(e, nil, study, study_file, { retry_count: attempt})
            Rails.logger.error "terminal error in UploadCleanupJob for #{study.accession}:#{study_file.bucket_location}:#{study_file.id}; #{e.message}"
            message = "<p>The following failure occurred when attempting to clean up #{study.firecloud_project}/#{study.firecloud_workspace}:#{study_file.bucket_location}</p>"
            message += "<hr /><p>#{e.class.name}: #{e.message}</p>"
            SingleCellMailer.admin_notification('UploadCleanupJob failure', nil, message).deliver_now
          end
        end
      end
    end
  end

  # poller to check for failed uploads and remove them automatically since users cannot delete these files
  # any file that has been stuck in 'uploading' for more that 24 hours that is not being parsed and has no
  # generation tag is considered a 'failed' upload and will be removed
  def self.find_and_remove_failed_uploads
    date_threshold = 1.day.ago.in_time_zone
    # make sure to exclude links to external sequence data with human_fastq_url: nil
    failed_uploads = StudyFile.where(:status.in => ['uploading', nil], generation: nil, :created_at.lte => date_threshold,
                                     human_fastq_url: nil, :parse_status.in => ['unparsed', nil])
    failed_uploads.each do |study_file|
      # final sanity check - see if there is a file in the bucket of the same size
      # this might happen if the post-upload action to update 'status' fails for some reason
      remote_file = ApplicationController.firecloud_client.get_workspace_file(study_file.study.bucket_id, study_file.bucket_location)
      if remote_file.present? && remote_file.size == study_file.upload_file_size
        study_file.update(status: 'uploaded', generation: remote_file.generation.to_s)
        next
      else
        Rails.logger.info "Deleting failed upload for #{study_file.upload_file_name}:#{study_file.id} from #{study_file.study.accession}"
        study_file.remove_local_copy if study_file.is_local?
        begin
          study = study_file.study
          unless study_file.queued_for_deletion
            SingleCellMailer.notify_user_upload_fail(study_file, study, study.user).deliver_now
          end
        rescue => e
          ErrorTracker.report_exception(e, nil)
          Rails.logger.error "Unable to notify user of upload failure: #{e.class}:#{e.message}"
        end
        DeleteQueueJob.new(study_file).perform
      end
    end
  end
end
