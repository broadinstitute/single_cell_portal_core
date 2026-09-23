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

  validates_presence_of :name, :checkout_session_id, :payment_intent_id, :customer_email
  validates_uniqueness_of :study_accession, scope: [:name, :checkout_session_id]
  validates_uniqueness_of :checkout_session_id, :payment_intent_id
  validates_inclusion_of :payment_status, in: Purchase::PAYMENT_STATUSES

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

  # find or initialize from Stripe::Checkout::Session or Stripe::PaymentIntent object
  # 
  # * *params*
  #   - +object+ (Stripe::Checkout::Session, Stripe::PaymentIntent) => Stripe object to use for initialization
  #   
  # * *returns*
  #   - (Purchase)
  def self.find_or_intialize_from(object)
    existing = Purchase.any_of( {checkout_session_id: object.id }, { payment_intent_id: object.id } )
    if existing.exists?
      return existing.first
    end

    case object.class.name
    when 'Stripe::Checkout::Session'
      purchased_item = object.line_items.data.first
      Purchase.new(
        name: purchased_item.description,
        amount: object.amount_total / 100.0, # amount is provided in cents
        checkout_session_id: object.id,
        payment_intent_id: object.payment_intent,
        customer_email: object.customer_email,
        study_accession: object.metadata.study_accession,
        sale_date: Time.at(object.created).in_time_zone,
        payment_status: payment_status_from(object)
      )
    when 'Stripe::PaymentIntent'
      purchase = Purchase.new(
        amount: object.amount / 100.0, # amount is provided in cents
        checkout_session_id: object.payment_details.order_reference,
        payment_intent_id: object.id,
        customer_email: object.receipt_email,
        sale_date: Time.at(object.created).in_time_zone,
        payment_status: payment_status_from(object)
      )
      checkout = purchase.checkout_session
      purchased_item = checkout.line_items.data.first
      purchase.name = purchased_item.description
      purchase.study_accession = checkout.metadata.study_accession
      purchase
    else
      raise TypeError, "source object is incompatible type: #{object.class.name}, must be one of #{SUPPORTED_CLASSES.join(', ')}"
    end
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