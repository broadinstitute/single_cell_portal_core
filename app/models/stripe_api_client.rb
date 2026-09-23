# lightweight wrapper for the Stripe API
# encapsulates business logic for cleaner interface to Stripe SDK
class StripeApiClient
  def initialize
    @client = Stripe::StripeClient.new(ENV['STRIPE_API_KEY'])
  end

  # list available products
  #
  # * *returns*
  #   - (Array<Stripe::Product>)
  def products
    @client.v1.products.list.data.reject {|p| p.description.include?('created by Stripe CLI') }
  end

  # get a single product
  #
  # * *params*
  #   - +product_id+ (String)
  #   
  # * *returns*
  #   - (Stripe::Product)
  def product(product_id)
    @client.v1.products.retrieve(product_id)
  end

  # list available checkout sessions
  #
  # * *returns*
  #   - (Array<Stripe::Checkout::Session>)
  def checkout_sessions
    @client.v1.checkout.sessions.list.data
  end

  # get a single checkout session
  #
  # * *params*
  #   - +session_id+ (String)
  #
  # * *returns*
  #   - (Array<Stripe::Checkout::Session>)
  def checkout_session(session_id)
    @client.v1.checkout.sessions.retrieve(session_id, { expand: ['line_items'] })
  end

  # list available payments
  #
  # * *returns*
  #   - (Array<Stripe::Product>)
  def payment_intents
    @client.v1.payment_intents.list.data
  end

  # get single products
  #
  # * *params*
  #   - +payment_id+ (String)
  #
  # * *returns*
  #   - (Array<Stripe::Product>)
  def payment_intent(payment_id)
    @client.v1.payment_intents.retrieve(payment_id)
  end

  # create a checkout session for a user requesting a private study exemption
  # this allows the user to keep a private study longer than the cutoff date
  #
  # * *params*
  #   - +product_id+ (String)   => ID of Stripe product
  #   - +user+ (User)           => User supplying payment
  #   - +study+ (Study)         => referenced Study
  #   - +success_path+ (String) => callback path after successful payment
  #
  # * *returns*
  #   - (Stripe::Checkout::Session) 
  def create_private_study_checkout(product_id, user, study, success_path)
    stripe_product = product(product_id)
    @client.v1.checkout.sessions.create({
      line_items: [
        price: stripe_product.default_price,
        quantity: 1
      ],
      customer_email: user.email,
      metadata: {
        study_accession: study.accession
      },
      mode: 'payment',
      success_url: "#{RequestUtils.get_base_url}#{success_path}"
    })
  end
end