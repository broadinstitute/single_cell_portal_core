class Purchase
  include Mongoid::Document
  include Mongoid::Timestamps

  PAYMENT_STATUSES = %w[unpaid processing paid].freeze
  SUPPORTED_CLASSES = [Stripe::Checkout::Session, Stripe::PaymentIntent].freeze

  field :name, type: String
  field :amount, type: Float
  field :checkout_session_id, type: String
  field :payment_intent_id, type: String
  field :customer_email, type: String
  field :study_accession, type: String
  field :sale_date, type: DateTime
  field :payment_status, type: String, default: 'unpaid'

  validates :name, :checkout_session_id, :payment_intent_id, :customer_email, presence: true
  validates :study_accession, uniqueness: { scope: [:name, :checkout_session_id] }
  validates :checkout_session_id, :payment_intent_id, uniqueness: true
  validates :payment_status, inclusion: { in: Purchase::PAYMENT_STATUSES }

  def stripe_client
    @stripe_client ||= StripeApiClient.new
  end

  def checkout_session
    stripe_client.checkout_session(checkout_session_id)
  end

  def payment_intent
    stripe_client.payment_intent(payment_intent_id)
  end

  def associated_user
    User.find_by(email: customer_email)
  end

  def associated_study
    return nil unless associated_user

    Study.find_by(accession: study_accession, user_id: associated_user.id)
  end

  def paid?
    payment_status == 'paid'
  end

  # find or initialize from Stripe::Checkout::Session object
  # 
  # * *params*
  #   - +object+ (Stripe::Checkout::Session)
  #   
  # * *returns*
  #   - (Purchase)
  def self.find_or_intialize_from(checkout)
    raise TypeError, "incompatible object type: #{checkout.class}" unless checkout.is_a?(Stripe::Checkout::Session)

    registered_purchase = Purchase.find_by(checkout_session_id: checkout.id)
    return registered_purchase if registered_purchase

    purchased_item = checkout.line_items.data.first
    Purchase.new(
      name: purchased_item.description,
      amount: checkout.amount_total / 100.0, # amount is provided in cents
      checkout_session_id: checkout.id,
      payment_intent_id: checkout.payment_intent,
      customer_email: checkout.customer_email,
      study_accession: checkout.metadata.study_accession,
      sale_date: Time.at(checkout.created).in_time_zone,
      payment_status: payment_status_from(checkout)
    )
  end

  def self.payment_status_from(object)
    object_payment_status = object.try(:payment_status) || object.try(:status)

    case object_payment_status.to_s
    when 'paid', 'succeeded'
      'paid'
    when 'processing'
      'processing'
    else
      'unpaid'
    end
  end
end