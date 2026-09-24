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
    @other_study = FactoryBot.create(:detached_study,
                               name_prefix: 'PurchasesControllerTest Study 2',
                               public: false,
                               user: @user,
                               test_array: @@studies_to_clean)
    @purchase = Purchase.new(
      study_accession: @study.accession,
      customer_email: @user.email,
      checkout_session_id: 'co_test_12345',
      payment_intent_id: 'pi_12345',
      sale_date: DateTime.now.in_time_zone,
      amount: 10.00,
      payment_status: 'paid'
    )
    FeatureFlag.create(name: 'enable_purchases_ux', default_value: true)
  end

  after(:all) do
    FeatureFlag.find_by(name: 'enable_purchases_ux')&.destroy
  end

  test 'should load purchases' do
    sign_in @user
    mock = Minitest::Mock.new
    mock.expect :products, [Stripe::Product.new(id: 'prod_1234', default_price: 'price_1234')]
    StripeApiClient.stub :new, mock do
      get purchases_path
      assert_response :success
      assert_select "select#product_study_accession" do
        assert_select "option", value: @other_study.accession
      end
    end
  end

  test 'should create checkout session' do
    sign_in @user
    session_url = "https://checkout.stripe.com/c/pay/cs_test_12345"
    mock_session = Minitest::Mock.new
    mock_session.expect :url, session_url
    mock = Minitest::Mock.new
    mock.expect :create_private_study_checkout, mock_session, [String, @user, @other_study, String]
    StripeApiClient.stub :new, mock do
      post create_stripe_checkout_path,
           params: { product: { product_id: 'prod_1234', study_accession: @other_study.accession } }
      assert_redirected_to session_url
    end
  end
end