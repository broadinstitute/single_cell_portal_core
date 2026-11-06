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

  test 'should handle nil file size' do
    starting_quota = @user.daily_download_quota
    DownloadQuotaService.increment_user_quota(@user, nil)
    @user.reload
    assert_equal starting_quota, @user.daily_download_quota
  end

  test 'should calculate GB in excess of quota' do
    AdminConfiguration.find_or_create_by(
      config_type: 'Daily User Download Quota', value: '1', value_type: 'Numeric', multiplier: 'megabyte'
    )
    assert_equal 0, DownloadQuotaService.gb_in_excess_of_quota(@user, 500.kilobytes)
    assert_equal 1, DownloadQuotaService.gb_in_excess_of_quota(@user, 2.megabytes)
    @user.update(daily_download_quota: 2.terabytes)
    assert_equal 1, DownloadQuotaService.gb_in_excess_of_quota(@user, 1.gigabyte)
  end

  test 'should create data egress checkout session' do
    AdminConfiguration.find_or_create_by(
      config_type: 'Daily User Download Quota', value: '1', value_type: 'Numeric', multiplier: 'megabyte'
    )
    gb_excess = 5
    file_info = { 
      success_path: "/single_cell/purchases/success",
      accession: @study.accession,
      download_identifier: @study_file.id.to_s
    }
    mock = Minitest::Mock.new
    mock_product = Minitest::Mock.new
    mock_product.expect :name, 'Data Egress Charge'
    mock_product.expect :nil?, false
    mock_product.expect :id, 'prod_12345'
    mock_session = Minitest::Mock.new
    mock_session.expect :object, 'checkout.session'
    mock_session.expect :url, 'https://stripe.com/checkout/session/test'
    mock_session.expect :success_url, file_info[:success_path]

    mock.expect :products, [mock_product]
    mock.expect :create_data_egress_checkout_session, 
                mock_session,
                ['prod_12345', @user, gb_excess, file_info]
    StripeApiClient.stub :new, mock do
      checkout_session = DownloadQuotaService.data_egress_checkout(@user, gb_excess, file_info)
      assert_equal 'checkout.session', checkout_session.object
      assert checkout_session.url.present?
      assert checkout_session.success_url.ends_with? file_info[:success_path]
      mock.verify
      mock_product.verify
      mock_session.verify
    end
  end
end
