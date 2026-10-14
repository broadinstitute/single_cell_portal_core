require 'integration_test_helper'
require 'test_helper'
require 'includes_helper'

class PurchasesControllerTest < ActionDispatch::IntegrationTest
  before(:all) do
    @user = FactoryBot.create(:user, test_array: @@users_to_clean)
    @study = FactoryBot.create(:detached_study,
                               name_prefix: 'PurchasesControllerTest Study',
                               public: false,
                               user: @user,
                               test_array: @@studies_to_clean)
    @cluster_file = FactoryBot.create(:cluster_file, name: 'cluster.txt', upload_file_size: 10.gigabytes, study: @study)
    @purchase = Purchase.create(
      name: 'Data Egress Charge',
      study_accession: @study.accession,
      customer_email: @user.email,
      checkout_session_id: 'co_test_12345',
      payment_intent_id: 'pi_12345',
      download_identifier: @cluster_file.id.to_s,
      sale_date: DateTime.now.in_time_zone,
      amount: 1.20,
      payment_status: 'paid',
      fulfilled: true
    )
    FeatureFlag.create(name: 'enable_purchases_ux', default_value: true)
  end

  after(:all) do
    FeatureFlag.find_by(name: 'enable_purchases_ux')&.destroy
    Purchase.destroy_all
  end

  test 'should load purchases' do
    sign_in @user
    get purchases_path
    assert_response :success
    assert_select "table#purchases tbody tr" do
      assert_select "td.study-accession", text: @study.accession
    end
  end
end