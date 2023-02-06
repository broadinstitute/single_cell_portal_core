# custom exceptions controller to render error views
class ExceptionsController < ApplicationController
  layout 'application'

  def render_error
    RequestUtils.log_exception(request, params, user: current_user, study: @study)
    respond_to do |format|
      format.html { render action: 'render_error', status: :internal_server_error }
      format.json do
        render json: RequestUtils.exception_json(request),
               status: :internal_server_error
      end
    end
  end

  def terra_tos; end
end
