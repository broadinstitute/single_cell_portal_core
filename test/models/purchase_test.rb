require 'test_helper'

class PurchaseTest < ActiveSupport::TestCase
  before(:all) do
    @user = FactoryBot.create(:user, test_array: @@users_to_clean)
    @study = FactoryBot.create(:detached_study,
                               name_prefix: 'Study File Test',
                               user: @user,
                               test_array: @@studies_to_clean)

    @study_file = FactoryBot.create(
      :study_file, name: 'dense.txt', file_type: 'Expression Matrix', upload_file_size: 100.gigabytes, study: @study
    )
    @purchase = Purchase.new(
      name: 'Data Egress Charge',
      study_accession: @study.accession,
      customer_email: @user.email,
      checkout_session_id: "co_test_#{SecureRandom.alphanumeric(24)}",
      payment_intent_id: "pi_#{SecureRandom.alphanumeric(24)}",
      download_identifier: @study_file.id.to_s,
      sale_date: DateTime.now.in_time_zone,
      amount: 12.0,
      payment_status: 'paid',
      fulfilled: true
    )
  end

  test 'should load Stripe client' do
    client = @purchase.stripe_client
    assert client.is_a?(StripeApiClient)
    assert_equal client.__id__, @purchase.stripe_client.__id__
  end

  test 'should load checkout session' do
    mock = Minitest::Mock.new
    mock.expect :checkout_session, Stripe::Checkout::Session.new, [@purchase.checkout_session_id]
    @purchase.stub :stripe_client, mock do
      checkout_session = @purchase.checkout_session
      assert checkout_session.present?
      assert checkout_session.is_a?(Stripe::Checkout::Session)
      mock.verify
    end
  end

  test 'should load payment intest' do
    mock = Minitest::Mock.new
    mock.expect :payment_intent, Stripe::PaymentIntent.new, [@purchase.payment_intent_id]
    @purchase.stub :stripe_client, mock do
      payment_intent = @purchase.payment_intent
      assert payment_intent.present?
      assert payment_intent.is_a?(Stripe::PaymentIntent)
      mock.verify
    end
  end

  test 'should load user' do
    assert_equal @purchase.associated_user, @user
  end

  test 'should load associated study' do
    assert_equal @purchase.associated_study.accession, @study.accession
    new_purchase = Purchase.new
    assert_nil new_purchase.associated_study
  end

  test 'should load associated download object' do
    assert_equal @purchase.associated_download, @study_file
  end

  test 'should determine if purchase is paid' do
    assert @purchase.paid?
    new_purchase = Purchase.new
    assert_not new_purchase.paid?
  end

  test 'should create new purchase from checkout session' do
    new_study_file = FactoryBot.create(
      :study_file, name: 'raw.txt', file_type: 'Expression Matrix', upload_file_size: 100.gigabytes, study: @study
    )
    now = Time.now
    mock = Minitest::Mock.new
    mock.expect :is_a?, true, [Stripe::Checkout::Session]
    metadata_mock = Minitest::Mock.new
    metadata_mock.expect :app_env, 'test'
    metadata_mock.expect :study_accession, @study.accession
    metadata_mock.expect :download_identifier, new_study_file.id.to_s
    item_mock = Minitest::Mock.new
    item_mock.expect :description, 'Data Egress Charge'
    line_items_mock = Minitest::Mock.new
    line_items_mock.expect :data, [item_mock]
    mock.expect :line_items, line_items_mock
    mock.expect :amount_total, 10000
    2.times { mock.expect :id, @purchase.checkout_session_id }
    3.times { mock.expect :metadata, metadata_mock }
    mock.expect :payment_intent, "pi_#{SecureRandom.alphanumeric(24)}"
    mock.expect :customer_email, @user.email
    mock.expect :created, now.to_i
    mock.expect :try, 'paid', [:payment_status]

    new_purchase = Purchase.find_or_intialize_from(mock)
    assert new_purchase.valid?
    assert_equal @study, new_purchase.associated_study
    assert_equal new_study_file, new_purchase.associated_download
    assert new_purchase.paid?
    assert_equal 100.0, new_purchase.amount
    mock.verify
    metadata_mock.verify
    line_items_mock.verify
    item_mock.verify
  end

  test 'should load payment status from object' do
    mock = Minitest::Mock.new
    mock.expect :try, 'succeeded', [:payment_status]
    assert_equal 'paid', Purchase.payment_status_from(mock)
    mock = Minitest::Mock.new
    mock.expect :try, 'processing', [:payment_status]
    assert_equal 'processing', Purchase.payment_status_from(mock)
    mock = Minitest::Mock.new
    mock.expect :try, 'not supported', [:payment_status]
    assert_equal 'unpaid', Purchase.payment_status_from(mock)
  end
end