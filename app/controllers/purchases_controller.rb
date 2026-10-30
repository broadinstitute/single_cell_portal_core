# handle Stripe purchases for authenticated user
class PurchasesController < ApplicationController
  before_action :authenticate_user!
  before_action :check_feature_flag

  def index
    @purchases = Purchase.where(customer_email: current_user.email)
  end

  private 

  def check_feature_flag
    unless current_user.feature_flag_for('enable_purchases_ux')
      redirect_to site_path, alert: "The requested feature is not enabled."
    end
  end
end