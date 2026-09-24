# handle Stripe purchases for authenticated user
class PurchasesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_stripe_client, except: :successful_purchase
  before_action :check_feature_flag

  def index
    @purchases = Purchase.where(customer_email: current_user.email)
    @products = @stripe_client.products
    @private_studies = Study.where(user_id: current_user.id, detached: false, queued_for_deletion: false, public: false).reject {|s| s.has_purchases? }
  end

  # create a new checkout session and redirect user to Stripe platform to complete purchase
  def create_stripe_checkout
    study = current_user.studies.find_by(accession: product_params[:study_accession])
    checkout_session = @stripe_client.create_private_study_checkout(
      product_params[:product_id], current_user, study, successful_purchase_path
    )
    redirect_to checkout_session.url, status: :see_other, allow_other_host: true
  end

  def successful_purchase; end

  private 

  def product_params
    params.require(:product).permit(:product_id, :study_accession)
  end

  def set_stripe_client
    @stripe_client = StripeApiClient.new
  end

  def check_feature_flag
    unless current_user.feature_flag_for('enable_purchases_ux')
      redirect_to site_path, alert: "The requested feature is not enabled."
    end
  end
end
