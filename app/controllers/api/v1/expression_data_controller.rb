module Api
  module V1
    class ExpressionDataController < ApiBaseController
      include Concerns::Authenticator
      include Concerns::StudyAware
      include Swagger::Blocks

      before_action :set_current_api_user!
      before_action :set_study
      before_action :check_study_view_permission


      # Returns the specified expression data for the gene within the given study, optimized for rendering
      # by the SCP UI.
      # We agreed that there would be no swagger docs for this endpoint, as it is not intended
      # to be used other than by the SCP UI, and may change dramatically
      def show
        if (!@study.has_expression_data? || !@study.can_visualize_clusters?)
          render json: {error: "Study #{@study.accession} does not support expression rendering"}, status: 400
        end
        data_type = params[:data_type]
        if (data_type == 'violin')
          render_violin
        elsif (data_type == 'annotations')
          render_annotation_values
        else
          render json: {error: "Unknown expression data type: #{data_type}"}, status: 400
        end

      end

      def render_violin
        cluster = ApiParamUtils.get_cluster_group(params, @study)
        selected_annotation = ApiParamUtils.get_selected_annotation(params, @study, cluster)
        subsample = params[:subsample].blank? ? nil : params[:subsample].to_i
        gene = @study.genes.by_name_or_id(params[:gene], @study.expression_matrix_files.map(&:id))

        render_data = ExpressionRenderingService.get_global_expression_render_data(
          @study, subsample, gene, cluster, selected_annotation, params[:boxpoints], current_api_user
        )
        render json: render_data, status: 200
      end

      def render_annotation_values
        cluster = ApiParamUtils.get_cluster_group(params, @study)
        annotation = ApiParamUtils.get_selected_annotation(params, @study, cluster)
        render json: annotation, status: 200
      end
    end
  end
end
