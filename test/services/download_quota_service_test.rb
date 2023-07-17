require 'test_helper'

class DownloadQuotaServiceTest < ActiveSupport::TestCase

  before(:all) do
    @user = FactoryBot.create(:admin_user, test_array: @@users_to_clean, daily_download_quota: 1.megabyte)
    @study = FactoryBot.create(:detached_study,
                               name_prefix: 'DownloadQuotaService test',
                               public: true,
                               user: @user,
                               test_array: @@studies_to_clean)
    @study_file = FactoryBot.create(:expression_file,
                                    study: @study,
                                    name: 'matrix.txt',
                                    generation: '123456',
                                    upload_file_size: 1.gigabyte)
  end

  teardown do
    @user.update(daily_download_quota: 1.megabyte)
    AdminConfiguration.find_by(config_type: 'Daily User Download Quota')&.destroy
  end

  test 'should grant quota exemption' do
    AdminConfiguration.find_or_create_by(
      config_type: 'Daily User Download Quota', value: '1', value_type: 'Numeric', multiplier: 'megabyte'
    )
    assert DownloadQuotaService.download_exceeds_quota?(@user, @study_file.upload_file_size)
    DownloadQuotaService.grant_user_exemption(@user)
    assert_not DownloadQuotaService.download_exceeds_quota?(@user, @study_file.upload_file_size)
  end

  test 'should reset download quotas' do
    assert_equal 1.megabyte, @user.daily_download_quota
    DownloadQuotaService.reset_all_quotas
    @user.reload
    assert_equal 0, @user.daily_download_quota
  end

  test 'should detect quota exceptions' do
    assert_not DownloadQuotaService.download_exceeds_quota?(@user, @study_file.upload_file_size)
    @user.update(daily_download_quota: 2.terabytes)
    assert DownloadQuotaService.download_exceeds_quota?(@user, @study_file.upload_file_size)
  end

  test 'should increment user quota' do
    starting_quota = @user.daily_download_quota
    DownloadQuotaService.increment_user_quota(@user, @study_file.upload_file_size)
    @user.reload
    assert_equal starting_quota + @study_file.upload_file_size, @user.daily_download_quota
  end

  test 'should retrieve download quota value' do
    assert_equal 2.terabytes, DownloadQuotaService.download_quota
    AdminConfiguration.find_or_create_by(
      config_type: 'Daily User Download Quota', value: '1', value_type: 'Numeric', multiplier: 'megabyte'
    )
    assert_equal 1.megabyte, DownloadQuotaService.download_quota
  end
end
