class Purchase
  include Mongoid::Document
  include Mongoid::Timestamps

  field :name, type: String
  field :checkout_session_id, type: String
  field :payment_intent_id, type: String
  field :customer_email, type: String
  field :study_accession, type: String
  field :paid, type: Mongoid::Boolean, default: false

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
end