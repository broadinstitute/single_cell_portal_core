require 'test_helper'

class StripeApiClientTest < ActiveSupport::TestCase
  
  before(:all) do
    @stripe_client = StripeApiClient.new
    @user = FactoryBot.create(:user, test_array: @@users_to_clean)
    @study = FactoryBot.create(:detached_study,
                               name_prefix: "StripeApiClient Testing Study",
                               description: 'SCP testing study for StripeApiClient integration',
                               public: false,
                               user: @user,
                               test_array: @@studies_to_clean)
  end

  test 'should instantiate client' do
    client = StripeApiClient.new
    assert client.is_a?(StripeApiClient)
    embedded_client = client.instance_variable_get(:@client)
    assert embedded_client.is_a?(Stripe::StripeClient)
  end

  test 'should list products' do
    products = @stripe_client.products
    assert products.any?
  end

  test 'should get product' do
    product_id = @stripe_client.products.sample&.id
    skip "did not get product id" if product_id.nil?

    product = @stripe_client.product(product_id)
    assert product.is_a?(Stripe::Product)
  end

  test 'should list prices' do
    prices = @stripe_client.prices
    assert prices.any?
  end

  test 'should get price' do
    price_id = @stripe_client.prices.sample&.id
    skip "did not get price id" if price_id.nil?

    price = @stripe_client.price(price_id)
    assert price.is_a?(Stripe::Price)
  end

  test 'should list checkout sessions' do
    checkouts = @stripe_client.checkout_sessions
    assert checkouts.any?
  end

  test 'should get checkout session' do
    checkout_id = @stripe_client.checkout_sessions.sample&.id
    skip "did not get checkout_session id" if checkout_id.nil?

    checkout = @stripe_client.checkout_session(checkout_id)
    assert checkout.is_a?(Stripe::Checkout::Session)
  end

  test 'should list payment intents' do
    payments = @stripe_client.payment_intents
    assert payments.any?
  end

  test 'should get payment intent' do
    payment_id = @stripe_client.payment_intents.sample&.id
    skip "did not get payment_intent id" if payment_id.nil?

    payment = @stripe_client.payment_intent(payment_id)
    assert payment.is_a?(Stripe::PaymentIntent)
  end

  test 'should create checkout session for purchase' do
    product = @stripe_client.products.detect {|p| p.name == 'Private Study' }
    success_path = "/single_cell/purchases/success"
    checkout = @stripe_client.create_private_study_checkout(
      product.id, @user, @study, success_path
    )
    assert checkout.is_a?(Stripe::Checkout::Session)
    assert checkout.url.present?
    assert checkout.success_url.ends_with? success_path
    price = @stripe_client.price(product.default_price)
    assert_equal checkout.amount_total, price.unit_amount
    # expire checkout as a courtesy
    embedded_client = @stripe_client.instance_variable_get(:@client)
    embedded_client.v1.checkout.sessions.expire(checkout.id)
  end
end