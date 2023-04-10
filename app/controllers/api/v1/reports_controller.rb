module Api
  module V1
    # reports endpoint.  No swagger docs since this is admin-user only
    # This returns tsv files
    class ReportsController < ApiBaseController
      include ActionController::RequestForgeryProtection

      before_action :authenticate_admin_api_user!

      def show
        report_name = params[:report_name].to_sym
        response.headers['Content-Disposition'] = "attachment; filename=#{report_name}_data.tsv"
        begin
          render plain: ReportsService.get_report_data(report_name, view_context: params[:view_context])
        rescue ArgumentError => e
          render json: { error: e.message }, status: :bad_request
        end
      end
    end
  end
end
