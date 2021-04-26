module Api
  module V1
    module Visualization
      # API methods for visualizing cluster data
      # does NOT contain methods for editing clusters
      class ClustersController < ApiBaseController
        include Concerns::Authenticator
        include Concerns::StudyAware
        include Concerns::ApiCaching
        include Swagger::Blocks

        VALID_SCOPE_VALUES = ['study', 'cluster']
        VALID_TYPE_VALUES = ['group', 'numeric']
        VALID_CONSENSUS_VALUES = ['mean', 'median']

        before_action :set_current_api_user!
        before_action :set_study
        before_action :check_study_view_permission
        before_action :check_api_cache!
        after_action :write_api_cache!

        swagger_path '/studies/{accession}/clusters' do
          operation :get do
            key :tags, [
                'Visualization'
            ]
            key :summary, 'Get the default cluster and its sub-clusters for a study'
            key :description, 'Get the default cluster group and its constituent cluster annotations'
            key :operationId, 'study_clusters_path'
            parameter do
              key :name, :accession
              key :in, :path
              key :description, 'Accession of study'
              key :required, true
              key :type, :string
            end
            response 200 do
              schema do
                key :type, :array
                key :description, 'Array of all cluster group names for this study'
                items do
                  key :type, :string
                  key :description, 'Name of cluster'
                end
              end
            end
            extend SwaggerResponses::StudyControllerResponses
          end
        end

        # return a listing of all clusters
        def index
          render json: ClusterVizService.load_cluster_group_options(@study)
        end

        swagger_path '/studies/{accession}/clusters/{cluster_name}' do
          operation :get do
            key :tags, [
                'Visualization'
            ]
            key :summary, 'Get a cluster\'s visualization data for a study'
            key :description, 'Get the cluster group and its constituent cluster annotations.'
            key :operationId, 'study_cluster_path'
            parameter do
              key :name, :accession
              key :in, :path
              key :description, 'Accession of study'
              key :required, true
              key :type, :string
            end
            parameter do
              key :name, :cluster_name
              key :in, :path
              key :description, 'Name of cluster group.  Use "_default" to return the default cluster'
              key :required, true
              key :type, :string
            end
            parameter do
              key :name, :is_annotated_scatter
              key :in, :query
              key :description, 'Whether plot is an "Annotated Scatter", i.e. an annotation-based data array scatter plot.'
              key :type, :string
            end
            parameter do
              key :name, :annot_name
              key :in, :query
              key :description, 'Name of the annotation to categorize the cluster data. (blank for default annotation)'
              key :type, :string
            end
            parameter do
              key :name, :annot_type
              key :in, :query
              key :description, 'Type of the annotation to retrieve--numeric or category.   (blank for default annotation)'
              key :type, :string
            end
            parameter do
              key :name, :annot_scope
              key :in, :query
              key :description, 'Scope of the annotation to retrieve--study or cluster.  (blank for default annotation)'
              key :type, :string
            end
            parameter do
              key :name, :include
              key :in, :query
              key :description, 'Specify specific return inclusions. "coordinates" or "annotation" (blank returns everything)'
              key :type, :string
            end
            response 200 do
              key :description, 'Scatter plot visualization of cluster, suitable for rendering in Plotly'
            end
            extend SwaggerResponses::StudyControllerResponses
          end
        end

        def show
          cluster = nil
          if params[:cluster_name] == '_default' || params[:cluster_name].empty?
            cluster = @study.default_cluster
            if cluster.nil?
              render json: {error: 'No default cluster exists'}, status: 404 and return
            end
          else
            cluster_name = params[:cluster_name]
            cluster = @study.cluster_groups.find_by(name: cluster_name)
            if cluster.nil?
              render json: {error: "No cluster named #{cluster_name} could be found"}, status: 404 and return
            end
          end
          begin
            viz_data = self.class.get_cluster_viz_data(@study, cluster, params)
          rescue ArgumentError => e
            render json: {error: e.message}, status: 404 and return
          end
          render json: viz_data
        end

        # packages up a bunch of calls to rendering service endpoints for a response object
        def self.get_cluster_viz_data(study, cluster, url_params)
          annot_params = AnnotationsController.get_annotation_params(url_params)
          annotation = AnnotationVizService.get_selected_annotation(study,
                                                       cluster: cluster,
                                                       annot_name: annot_params[:name],
                                                       annot_type: annot_params[:type],
                                                       annot_scope: annot_params[:scope])
          if !annotation
            raise ArgumentError, "Annotation #{annot_params[:annot_name]} could not be found"
          end

          subsample = get_selected_subsample_threshold(url_params[:subsample], cluster)
          consensus = url_params[:consensus].blank? ? nil : url_params[:consensus]

          default_data_includes = ['coordinates', 'expression', 'annotation', 'cells']
          data_includes = url_params[:includes].blank? ? default_data_includes : url_params[:includes].split(',')
          include_coordinates = data_includes.include?('coordinates')
          include_expression = data_includes.include?('expression')
          include_annotation = data_includes.include?('annotation')
          include_cells = data_includes.include?('cells')

          colorscale = url_params[:colorscale]
          if colorscale.blank?
            colorscale = study.default_color_profile
            if colorscale.blank?
              colorscale = 'Reds'
            end
          end

          is_annotated_scatter = !url_params[:is_annotated_scatter].blank?

          titles = ClusterVizService.load_axis_labels(cluster)
          plot_data = nil
          genes = RequestUtils.get_genes_from_param(study, url_params[:gene])

          if url_params[:gene].blank?
            # For "Clusters" tab in default view of Explore tab
            plot_data = ClusterVizService.load_cluster_group_data_array_points(study, cluster, annotation, subsample, include_coordinates, include_cells)
            if cluster.is_3d? && include_coordinates
              range = ClusterVizService.get_range(cluster, plot_data)
            end
          else
            if genes.count == 0
              # all searched genes do not exist in this study
              raise ArgumentError, "No genes in this study matched your search"
            end
            # For single-gene view of Explore tab (or collapsed multi-gene)
            is_collapsed_view = genes.length > 1 && consensus.present?
            titles[:magnitude] = ExpressionVizService.load_expression_axis_title(study)

            if is_annotated_scatter
              # For "Annotated scatter" tab, shown in first tab for numeric annotations
              if is_collapsed_view
                plot_data = ExpressionVizService.load_gene_set_annotation_based_scatter(study, genes, cluster, annotation, consensus, subsample, y_axis_title)
              else
                plot_data = ExpressionVizService.load_annotation_based_data_array_scatter(
                  study, genes[0], cluster, annotation, subsample, y_axis_title)
              end
              range = ClusterVizService.set_range(cluster, plot_data.values)
              titles = {
                x: annot_params[:name],
                y: titles[:magnitude]
              }
            else
              # For "Scatter" tab
              if is_collapsed_view
                plot_data = ExpressionVizService.load_gene_set_expression_data_arrays(study, genes, cluster, annotation, consensus, subsample, y_axis_title, colorscale)
              else
                plot_data = ExpressionVizService.load_expression_data_array_points(study, genes[0], cluster, annotation, subsample, !include_coordinates)
              end
            end
          end

          if cluster.is_3d? && cluster.has_range?
            aspect = ClusterVizService.compute_aspect_ratios(range)
          end

          axes_full = {
            titles: titles,
            ranges: range,
            aspects: aspect
          }

          coordinate_labels = ClusterVizService.load_cluster_group_coordinate_labels(cluster)
          {
            "data": plot_data,
            "pointSize": study.default_cluster_point_size,
            "showClusterPointBorders": study.show_cluster_point_borders?,
            "description": cluster.study_file.description,
            "is3D": cluster.is_3d?,
            "isSubsampled": cluster.subsampled?,
            "isAnnotatedScatter": is_annotated_scatter,
            "numPoints": cluster.points,
            "domainRanges": cluster.domain_ranges,
            "axes": axes_full,
            "hasCoordinateLabels": cluster.has_coordinate_labels?,
            "coordinateLabels": coordinate_labels,
            "defaultPointOpacity": study.default_cluster_point_alpha,
            "cluster": cluster.name,
            "gene": genes.map {|g| g['name']}.join(', '),
            "annotParams": annotation,
            "subsample": subsample.nil? ? 'all' : subsample,
            "consensus": consensus
          }
        end

        def self.get_selected_subsample_threshold(param, cluster)
          subsample = nil
          if param.blank?
            # default to largest threshold available that is < 10K
            subsample = ClusterVizService.default_subsampling(cluster)
          elsif param == 'all'
            subsample = nil
          else
            subsample = param.to_i
          end
          subsample
        end
      end
    end
  end
end
