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
              key :name, :subsample
              key :in, :query
              key :description, 'Subsampling threshold'
              key :type, :integer
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
          viz_data = nil
          if User.feature_flag_for_instance(current_api_user, 'mock_viz_retrieval')
            render json: {media_url: self.class.get_fixed_size_response(cluster, params, current_api_user)} and return
          else
            viz_data = self.class.get_cluster_viz_data(@study, cluster, params)
          end
          if viz_data.nil?
            render json: {error: 'Annotation could not be found'}, status: 404 and return
          end
          render json: viz_data
        end

        # packages up a bunch of calls to rendering service endpoints for a response object
        def self.get_cluster_viz_data(study, cluster, url_params)
          annot_params = AnnotationsController.get_annotation_params(url_params)
          annotation = AnnotationVizService.get_selected_annotation(study,
                                                       cluster,
                                                       annot_params[:name],
                                                       annot_params[:type],
                                                       annot_params[:scope])
          if !annotation
            return nil
          end

          subsample = url_params[:subsample].blank? ? nil : url_params[:subsample].to_i
          consensus = url_params[:consensus].blank? ? nil : url_params[:consensus]

          colorscale = url_params[:colorscale].blank? ? 'Reds' : url_params[:colorscale]

          is_annotated_scatter = !url_params[:is_annotated_scatter].blank?

          titles = ClusterVizService.load_axis_labels(cluster)
          coordinates = nil
          genes = RequestUtils.get_genes_from_param(study, url_params[:gene])
          if url_params[:gene].blank?
            # For "Clusters" tab in default view of Explore tab
            coordinates = ClusterVizService.load_cluster_group_data_array_points(study, cluster, annotation, subsample, colorscale)
            if cluster.is_3d?
              range = ClusterVizService.set_range(cluster, coordinates.values)
            end
          else
            # For single-gene view of Explore tab (or collapsed multi-gene)
            is_collapsed_view = genes.length > 1 && consensus.present?
            y_axis_title = ExpressionVizService.load_expression_axis_title(study)

            if is_annotated_scatter
              # For "Annotated scatter" tab, shown in first tab for numeric annotations
              if is_collapsed_view
                coordinates = ExpressionVizService.load_gene_set_annotation_based_scatter(study, genes, cluster, annotation, consensus, subsample, y_axis_title)
              else
                coordinates = ExpressionVizService.load_annotation_based_data_array_scatter(
                  study, genes[0], cluster, annotation, subsample, y_axis_title)
              end
              range = ClusterVizService.set_range(cluster, coordinates.values)
              titles = {
                x: annot_params[:name],
                y: y_axis_title
              }
            else
              # For "Scatter" tab
              if is_collapsed_view
                coordinates = ExpressionVizService.load_gene_set_expression_boxplot_scores(study, genes, cluster, selected_annotation, consensus, subsample)
              else
                coordinates = ExpressionVizService.load_expression_data_array_points(study, genes[0], cluster, annotation, subsample, y_axis_title, colorscale)
              end
            end
          end

          if cluster.is_3d? && cluster.has_range?
            aspect = ClusterVizService.compute_aspect_ratios(range)
          end

          plot_data = ClusterVizService.transform_coordinates(coordinates, study, cluster, annotation)


          axes_full = {
            titles: titles,
            ranges: range,
            aspects: aspect
          }

          coordinate_labels = ClusterVizService.load_cluster_group_coordinate_labels(cluster)
          response_obj = {
            "data": plot_data,
            "description": cluster.study_file.description,
            "is3D": cluster.is_3d?,
            "isSubsampled": cluster.subsampled?,
            "isAnnotatedScatter": is_annotated_scatter,
            "numPoints": cluster.points,
            "domainRanges": cluster.domain_ranges,
            "axes": axes_full,
            "hasCoordinateLabels": cluster.has_coordinate_labels?,
            "coordinateLabels": coordinate_labels,
            "cluster": cluster.name,
            "gene": genes.map {|g| g['name']}.join(' ,'),
            "annotParams": annot_params
          }
          response_obj
        end

        # returns a string that can be immmediately passed to the front end for cluster visualization
        # the only parameter is the number of cells in the response
        # this method either randomly generates the data, or redirects to a pre-rendered, compressed JSON response
        # depending on the feature flag
        def self.get_fixed_size_response(cluster, params, user)
          num_cells = params[:subsample].to_i
          if User.feature_flag_for_instance(user, 'prerendered_json')
            study = cluster.study
            bucket_id = study.bucket_id
            filename = num_cells > 0 ? cluster.name + ".#{num_cells}.response.json" : cluster.name + ".response.json"
            cluster_remote_file = ApplicationController.firecloud_client.get_workspace_file(bucket_id, filename)
            return cluster_remote_file.media_url
          else
            num_annots = 10
            fake_annotations = num_annots.times.map { |n| "ant#{n}" }
            mock_response = {
              :description=>nil,
              :is3D=>false,
              :isSubsampled=>false,
              :isAnnotatedScatter=>false,
              :numPoints=>num_cells,
              :domainRanges=>nil,
              :axes=> {
                :titles=>{:x=>"X", :y=>"Y", :z=>"Z"},
                :ranges=>nil,
                :aspects=>nil
              },
              :hasCoordinateLabels=>true,
              :coordinateLabels=>[
                {:showarrow=>false, :x=>20.0, :y=>20.0, :text=>"Lower left", :font=>{:family=>"Helvetica Neue", :size=>10, :color=>"#333333"}},
                {:showarrow=>false, :x=>140.0, :y=>140.0, :text=>"Upper right", :font=>{:family=>"Helvetica Neue", :size=>10, :color=>"#333333"}},
                {:showarrow=>false, :x=>30.0, :y=>130.0, :text=>"Upper left", :font=>{:family=>"Helvetica Neue", :size=>10, :color=>"#333333"}},
                {:showarrow=>false, :x=>120.0, :y=>33.0, :text=>"Lower right", :font=>{:family=>"Helvetica Neue", :size=>10, :color=>"#333333"}}
              ],
              :cluster=>"cluster.tsv",
              :gene=>"",
              :annotParams=>{:name=>"biosample_id", :type=>"group", :scope=>"study"}
            }
            annot_size = num_cells / num_annots
            data = num_annots.times.map do |i|
              cells = annot_size.times.map {|ii| "gatc_gatc_gatc_c#{i}_#{ii}" }
              {
                x: annot_size.times.map { (((rand + 1) * (rand + 1)) * 17 + i * 14).round(3) },
                y: annot_size.times.map { (rand * 140).round(3) },
                cells: cells,
                name: "cluster #{i} (#{annot_size} points)",
                type: 'scattergl',
                mode: 'markers',
                marker: {:size=>3, :line=>{:color=>"rgb(40,40,40)", :width=>0}},
                opacity: 1.0,
                text: cells.map {|c| "<b>#{c}</b><br>#{fake_annotations[i]}"},
                annotations: fake_annotations
              }
            end
            mock_response[:data] = data
            return mock_response.to_json
          end
        end
      end
    end
  end
end
