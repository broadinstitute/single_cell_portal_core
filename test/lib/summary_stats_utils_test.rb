require 'test_helper'

class SummaryStatsUtilsTest < ActiveSupport::TestCase

  before(:all) do
    @now = DateTime.now
    @today = Time.zone.today
    @one_week_ago = @today - 1.week
    @one_month_ago = @today - 1.month
    # create some users
    @user = FactoryBot.create(:admin_user, test_array: @@users_to_clean)
    FactoryBot.create(:user, test_array: @@users_to_clean)
    FactoryBot.create(:api_user, test_array: @@users_to_clean)
    # create testing study with file in the bucket
    @study = FactoryBot.create(:study,
                               name_prefix: 'SummaryStatsUtils Study',
                               public: true,
                               user: @user,
                               test_array: @@studies_to_clean,
                               predefined_file_types: %w[cluster])
    DirectoryListing.create!(name: 'csvs', file_type: 'csv', files: [{name: 'foo.csv', size: 100, generation: '12345'}],
                             sync_status: true, study: @study)
  end

  test 'should get user counts' do
    # manually update all user's current_sign_in_at to mimic sign_in
    User.update_all(current_sign_in_at: @now)
    expected_user_count = User.count
    user_stats = SummaryStatsUtils.daily_total_and_active_user_counts
    assert_equal [:total, :active], user_stats.keys
    assert_equal expected_user_count, user_stats[:total]
    assert_equal expected_user_count, user_stats[:active]

    # exercise cutoff date
    user_stats = SummaryStatsUtils.daily_total_and_active_user_counts(end_date: @one_week_ago)
    assert_equal 0, user_stats[:total]
    assert_equal 0, user_stats[:active]
  end

  test 'should get analysis submission counts' do
    # manually insert a submission to check
    AnalysisSubmission.create!(submitter: User.first.email, submission_id: SecureRandom.uuid, analysis_name: 'test-analysis',
                               submitted_on: @now, firecloud_project: FireCloudClient::PORTAL_NAMESPACE,
                               firecloud_workspace: 'test-workspace')
    submission_count = SummaryStatsUtils.analysis_submission_count
    assert_equal 1, submission_count

    # exercise cutoff date
    submission_count = SummaryStatsUtils.analysis_submission_count(start_date: @one_month_ago, end_date: @one_week_ago)
    assert_equal 0, submission_count

    # clean up
    AnalysisSubmission.destroy_all
  end

  test 'should get study creation counts' do
    expected_study_count = Study.count
    studies_created = SummaryStatsUtils.daily_study_creation_count
    assert_equal expected_study_count, studies_created

    # exercise cutoff date
    studies_created = SummaryStatsUtils.daily_study_creation_count(end_date: @one_week_ago)
    assert_equal 0, studies_created
  end

  test 'should verify all remote files' do
    files_missing = SummaryStatsUtils.storage_sanity_check
    missing_csv = files_missing.detect {|entry| entry[:filename] == 'foo.csv'}
    reason = "File missing from bucket: #{@study.bucket_id}"
    assert missing_csv.present?, "Did not find expected missing file of 'foo.csv'"
    assert missing_csv[:study] == @study.name
    assert missing_csv[:owner] == @study.user.email
    assert missing_csv[:reason] == reason
  end

  test 'should get disk usage stats' do
    disk_usage_keys = [:total_space, :space_used, :space_free, :percent_used, :mount_point]
    disk_usage = SummaryStatsUtils.disk_usage
    assert_equal disk_usage_keys, disk_usage.keys
    disk_usage.each do |key, value|
      assert_not_nil value, "Did not find a value for #{key}: #{value}"
    end
  end

  test 'should get ingest run counts' do
    # testing the count of submissions is never going to be idempotent as it depends entirely on the number
    # of PRs and builds that have run in any given time frame
    # likely all we can do is prove that we get a number greater than 0, and then use a future cutoff date that should
    # return 0 as no runs have been initiated then yet
    ingest_runs = SummaryStatsUtils.ingest_run_count
    skip "Skipping as no ingest runs have been launched yet" if ingest_runs == 0
    assert ingest_runs > 0, "Should have found at least one ingest run for today, instead found: #{ingest_runs}"
    tomorrow = @today + 1.day
    runs_tomorrow = SummaryStatsUtils.ingest_run_count(start_date: tomorrow, end_date: tomorrow + 1.day)
    assert_equal 0, runs_tomorrow, "Should not have found any ingest runs for tomorrow: #{runs_tomorrow}"
  end

  test 'should get Study creation stats' do
    new_study = FactoryBot.create(:detached_study,
                                  name_prefix: 'creation history stats',
                                  user: @user,
                                  test_array: @@studies_to_clean)
    created_studies_info = SummaryStatsUtils.created_studies_info
    created_titles = created_studies_info.map{|creation| creation[:title]}
    assert created_titles.include?(new_study.name)
  end

  test 'should get Study deletion stats' do
    new_study = FactoryBot.create(:detached_study,
                                  name_prefix: 'deletion history stats',
                                  user: @user,
                                  test_array: @@studies_to_clean)
    new_study.destroy
    deleted_studies_info = SummaryStatsUtils.deleted_studies_info
    titles = deleted_studies_info.map{|deletion| deletion[:title]}
    assert titles.include?(new_study.name)
  end

  test 'should get Study update stats' do
    new_study = FactoryBot.create(:detached_study,
                                  name_prefix: 'update history stats',
                                  public: false,
                                  user: @user,
                                  test_array: @@studies_to_clean)
    new_study.update(public: true)
    cluster_file = FactoryBot.create(:cluster_file, name: 'clusterA.txt', study: new_study)
    cluster_file.update(description: 'test cluster file')
    updated_studies_info = SummaryStatsUtils.updated_studies_info(exclude_create_delete: false)
    study_update_infos = updated_studies_info.select{ |update| update[:accession] == new_study.accession }
    assert_equal 1, study_update_infos.length
    study_update = study_update_infos.first
    assert_equal new_study.name, study_update[:title]
    assert_equal({'public' => 1, 'file updates' => 2},  study_update[:updates])
  end

  test 'should get study stats' do
    studies = Study.where(queued_for_deletion: false)
    public = studies.where(public: true)
    existing_public = public.count
    existing_compliant = public.select { |s| s.metadata_file&.use_metadata_convention }.count
    stats = SummaryStatsUtils.study_counts
    assert_equal studies.count, stats[:all]
    assert_equal existing_public, stats[:public]
    assert_equal existing_compliant, stats[:compliant]
    new_study = FactoryBot.create(:detached_study,
                                  name_prefix: 'public compliant stats',
                                  user: @user,
                                  test_array: @@studies_to_clean)
    FactoryBot.create(:metadata_file, name: 'compliant.txt', study: new_study, use_metadata_convention: true)
    updated_stats = SummaryStatsUtils.study_counts
    updated_studies = studies.count
    updated_public = public.count
    updated__compliant = public.select { |s| s.metadata_file&.use_metadata_convention }.count
    assert_equal updated_studies, updated_stats[:all]
    assert_equal updated_public, updated_stats[:public]
    assert_equal updated__compliant, updated_stats[:compliant]
  end
end
