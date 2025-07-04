module Api
  module V1
    module Visualization
      # API methods for visualizing expression data
      # does NOT contain methods for editing expression data
      class ExpressionController < ApiBaseController
        include Concerns::ApiCaching

        before_action :set_current_api_user!
        before_action :set_study
        before_action :check_study_view_permission
        before_action :check_gene_limit
        before_action :validate_cache_request
        before_action :check_api_cache!
        before_action :set_cluster
        before_action :set_genes
        before_action :set_selected_annotation
        before_action :set_subsampling_threshold
        after_action :write_api_cache!

        # Returns the specified expression data for the gene within the given study, optimized for rendering
        # by the SCP UI.
        # We agreed that there would be no swagger docs for this endpoint, as it is not intended
        # to be used other than by the SCP UI, and may change dramatically

        swagger_path '/studies/{accession}/expression/{data_type}' do
          operation :get do
            key :tags, [
              'Visualization'
            ]
            key :summary, 'Get expression-based plot data for visualization'
            key :description, "Get expression-based plot data for use in visualization.  Supports violin/heatmap/dot plots." \
                              "\n\n<strong>NOTE: This endpoint may change frequently, so use with care.</strong>"
            key :operationId, 'study_visualization_expression_show'
            parameter do
              key :name, :accession
              key :in, :path
              key :description, 'Study accession number (e.g. SCPXXX)'
              key :required, true
              key :type, :string
            end
            parameter do
              key :name, :data_type
              key :in, :path
              key :description, 'Type of plot data requested'
              key :required, true
              key :type, :string
              key :enum, %w(violin heatmap morpheus dotplot)
            end
            parameter do
              key :name, :cluster
              key :in, :query
              key :description, 'Name of requested cluster (optional)'
              key :required, false
              key :type, :string
            end
            parameter do
              key :name, :genes
              key :in, :query
              key :description, 'List of requested genes (optional)'
              key :required, false
              key :type, :string
            end
            parameter do
              key :name, :annotation_name
              key :in, :query
              key :description, 'Name of requested annotation (optional, can pass "_default" for default annotation)'
              key :required, false
              key :type, :string
            end
            parameter do
              key :name, :annotation_type
              key :in, :query
              key :description, 'Type of requested annotation (optional)'
              key :required, false
              key :type, :string
              key :enum, %w(group numeric)
            end
            parameter do
              key :name, :annotation_scope
              key :in, :query
              key :description, 'Scope of requested annotation (optional)'
              key :required, false
              key :type, :string
              key :enum, %w(study cluster user)
            end
            parameter do
              key :name, :gene_list
              key :in, :query
              key :description, 'Name of gene list (optional)'
              key :required, false
              key :type, :string
            end
            response 200 do
              key :description, 'JSON plot data to be fed to JS visualization'
            end
            extend SwaggerResponses::StudyControllerResponses
          end
        end

        def show
          if (!@study.has_expression_data? || !@study.can_visualize_clusters?) && !params[:gene_list]
            render json: {
              error: "Study #{@study.accession} does not support expression rendering"
            }, status: :bad_request and return
          end

          if @annotation.nil?
            render json: { error: 'Requested annotation not found' }, status: :not_found and return
          end

          data_type = params[:data_type]
          case data_type
          when 'violin'
            render_violin
          when 'heatmap' # Only used for pre-computed heatmaps
            render_heatmap
          when 'morpheus'
            render_morpheus_json
          when 'dotplot'
            render_dotplot
          else
            render json: { error: "Unknown expression data type: #{data_type}" }, status: :bad_request
          end
        end

        def render_violin
          if @cluster.nil?
            render json: { error: 'Requested cluster not found' }, status: :not_found and return
          end

          if @genes.empty?
            if params[:genes].empty?
              render json: { error: 'You must supply at least one gene' }, status: :bad_request
            else
              render json: { error: 'No genes in this study matched your search' }, status: :not_found
            end
          else
            render_data = ExpressionVizService.get_global_expression_render_data(
              study: @study,
              subsample: @subsample,
              genes: @genes,
              cluster: @cluster,
              selected_annotation: @annotation,
              boxpoints: params[:boxpoints],
              consensus: params[:consensus]
            )
            render json: render_data, status: :ok
          end
        end

        # this is intended to provide morpheus compatibility, so it returns plain text, instead of json
        def render_heatmap
          if params[:gene_list]
            gene_list = @study.precomputed_scores.by_name(params[:gene_list])
            expression_data = gene_list&.to_gct
          else
            expression_data = ExpressionVizService.get_morpheus_text_data(
              genes: @genes, cluster: @cluster, collapse_by: params[:row_centered], file_type: :gct
            )
          end

          render plain: expression_data, status: :ok
        end

        # return data in JSON format for Morpheus to be shared across multiple instances
        def render_morpheus_json
          if @cluster.nil?
            render json: { error: 'Requested cluster not found' }, status: :not_found and return
          end

          expression_data = ExpressionVizService.get_morpheus_json_data(
            study: @study, genes: @genes, cluster: @cluster, annotation: @annotation, subsample_threshold: @subsample
          )

          render json: expression_data, status: :ok
        end

        def render_dotplot
          if @cluster.nil?
            render json: { error: 'Requested cluster not found' }, status: :not_found and return
          end

          expression_data = ExpressionVizService.load_precomputed_dot_plot_data(
            @study, @cluster, annotation: @annotation, genes: @genes
          )
          render json: expression_data, status: :ok
        end

        private

        # enforce a limit on number of genes allowed for visualization requests
        # see StudySearchService::MAX_GENE_SEARCH
        def check_gene_limit
          return true if params[:genes].blank? || params[:data_type] == 'dotplot'

          # render 422 if more than MAX_GENE_SEARCH as request fails internal validation
          num_genes = params[:genes].split(',').size
          if num_genes > StudySearchService::MAX_GENE_SEARCH
            MetricsService.log('search-too-many-genes', { numGenes: num_genes }, current_api_user, request:)
            render json: { error: StudySearchService::MAX_GENE_SEARCH_MSG }, status: :unprocessable_entity
          end
        end

        def set_cluster
          @cluster = ClusterVizService.get_cluster_group(@study, params)
        end

        def set_genes
          if params[:data_type] == 'dotplot'
            @genes = params[:genes].split(',').map(&:strip).reject(&:empty?)
          else
            @genes = RequestUtils.get_genes_from_param(@study, params[:genes])
          end
        end

        def set_selected_annotation
          @annotation = AnnotationVizService.get_selected_annotation(@study,
                                                                     cluster: @cluster,
                                                                     annot_name: params[:annotation_name],
                                                                     annot_type: params[:annotation_type],
                                                                     annot_scope: params[:annotation_scope])
        end

        def set_subsampling_threshold
          @subsample = ClustersController.get_selected_subsample_threshold(params[:subsample], @cluster)
        end
      end
    end
  end
end
