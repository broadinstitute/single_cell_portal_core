# lightweight wrapper for the Stripe API

class StripeApiClient
  def initialize
    @client = Stripe::StripeClient.new(ENV['STRIPE_API_KEY'])
  end

  def products
    @client.v1.products.list.data
  end

  def product(product_id)
    @client.v1.products.retrieve(product_id)
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
      success_url: "#{RequestUtils.get_base_url}/#{success_path}"
    })
  end
end