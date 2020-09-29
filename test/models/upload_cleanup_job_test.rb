require 'test_helper'

class UploadCleanupJobTest < ActiveSupport::TestCase

  def setup
    @study = Study.first
  end

  test 'should automatically remove failed uploads' do
    puts "#{File.basename(__FILE__)}: #{self.method_name}"

    # get starting counts, taking into account upstream tests that have deleted files
    beginning_file_count = StudyFile.where(queued_for_deletion: false).count
    existing_deletes = StudyFile.where(queued_for_deletion: true).pluck(:id)
    # run without any failed uploads to ensure good files aren't removed
    UploadCleanupJob.find_and_remove_failed_uploads
    failed_uploads = StudyFile.where(queued_for_deletion: true, :id.nin => existing_deletes).count
    assert failed_uploads == 0, "Should not have found any failed uploads but found #{failed_uploads}"

    # now simulate a failed upload and prove they are detected
    filename = 'expression_matrix_example_2.txt'
    file = File.open(Rails.root.join('test', 'test_data', filename))
    bad_upload = StudyFile.create(name: filename, study: @study, file_type: 'Expression Matrix', upload: file,
                                  status: 'uploading', created_at: 1.week.ago.in_time_zone)
    UploadCleanupJob.find_and_remove_failed_uploads
    failed_uploads = StudyFile.where(queued_for_deletion: true, :id.nin => existing_deletes).count
    assert failed_uploads == 1, "Should have found 1 failed upload but found #{failed_uploads}"
    bad_upload.reload
    assert bad_upload.queued_for_deletion, "Did not correctly mark #{bad_upload.name} as failed upload"

    # remove queued deletions
    StudyFile.delete_queued_files
    end_file_count = StudyFile.count
    assert_equal beginning_file_count, end_file_count,
                 "Study file counts do not match after removing failed uploads; #{beginning_file_count} != #{end_file_count}"

    puts "#{File.basename(__FILE__)}: #{self.method_name} successful!"
  end
end
