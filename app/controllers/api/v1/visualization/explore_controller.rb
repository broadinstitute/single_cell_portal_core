module Api
  module V1
    module Visualization
      # aggregation controller for methods needed for initial study visualization display
      # the goal of this controller is to be business-logic free, and only amalgamate calls
      # to other controller/service methods when needed to save server round-trips
      class ExploreController < ApiBaseController
        include Concerns::ApiCaching
        before_action :set_current_api_user!

        before_action :set_study
        before_action :check_study_view_permission

        # don't cache cluster_options or study_user_info, as those are user-dependent.
        before_action :check_api_cache!, except: [:cluster_options, :study_user_info]
        after_action :write_api_cache!, except: [:cluster_options, :study_user_info]


        swagger_path '/studies/{study_id}/explore' do
          operation :get do
            key :tags, [
                'Visualization'
            ]
            key :summary, 'Basic study visualization information'
            key :description, 'Returns overview of visualization properties for the given study'
            key :operationId, 'api_v1_studies_explore_path'
            parameter do
              key :name, :study_id
              key :in, :path
              key :description, 'ID of Study'
              key :required, true
              key :type, :string
            end
            response 200 do
              key :description, 'JSON of study visualization properties'
            end
            response 401 do
              key :description, ApiBaseController.unauthorized
            end
            response 403 do
              key :description, ApiBaseController.forbidden('edit Study')
            end
            response 404 do
              key :description, ApiBaseController.not_found(Study)
            end
            response 406 do
              key :description, ApiBaseController.not_acceptable
            end
          end
        end

=begin
        cluster {Object}: Cluster properties for visualization, if present

        taxonNames {Array} List of species scientific names

        inferCNVIdeogramFiles {Object}: inferCNV ideogram files, by file ID

        uniqueGenes (Array): List of unique gene names, for e.g. autocomplete

        ---

        clusterPointAlpha {Float}: opacity of cluster points in this study

        clusterGroupNames {Array}: all possible cluster groups for a study
=end

        def show
          # because this endpoint is cached for performance, we explicitly exclude user-specific information
          # (e.g. user annotations) from it
          explore_props = self.class.get_study_explore_info(@study, nil)
          render json: explore_props
        end

        swagger_path '/studies/{study_id}/explore/cluster_options' do
          operation :get do
            key :tags, [
                'Visualization'
            ]
            key :summary, 'Basic study visualization information'
            key :description, 'Returns overview of visualization properties for the given study'
            key :operationId, 'cluster_options_api_v1_studies_explore_path'
            parameter do
              key :name, :study_id
              key :in, :path
              key :description, 'ID of Study'
              key :required, true
              key :type, :string
            end
            response 200 do
              key :description, 'Annotation list, default_cluster, and subsampling thresholds'
            end
            response 401 do
              key :description, ApiBaseController.unauthorized
            end
            response 403 do
              key :description, ApiBaseController.forbidden('edit Study')
            end
            response 404 do
              key :description, ApiBaseController.not_found(Study)
            end
            response 406 do
              key :description, ApiBaseController.not_acceptable
            end
          end
        end

        def cluster_options
          render json: AnnotationVizService.get_study_annotation_options(@study, current_api_user)
        end

        def bam_file_info
          render json: {
            bamAndBaiFiles: @study.get_bam_files,
            gtfFiles: @study.get_genome_annotations_by_assembly
          }
        end

        def study_user_info
          render json: {
            annotations: AnnotationVizService.available_annotations(@study, cluster: nil, current_user: current_api_user),
            canEdit: @study.can_edit?(current_api_user),
          }
        end

        def self.get_study_explore_info(study, user)
          default_cluster = study.default_cluster
          ideogram_files = ExpressionVizService.get_infercnv_ideogram_files(study)

          if default_cluster.present?
            cluster = {
              numPoints: default_cluster.points,
              isSubsampled: default_cluster.subsampled?
            }
          else
            cluster = nil
          end
          spatial_group_options = ClusterVizService.load_spatial_options(study)
          image_options = ClusterVizService.load_image_options(study)
          bam_bundle_list = study.study_file_bundles.where(bundle_type: 'BAM').pluck(:original_file_list)
          precomputed_scores = ActiveRecordUtils.pluck_to_hash(
            study.study_files.where(file_type: 'Gene List'),
              [:name, :heatmap_file_info, :description]
          )
          {
            cluster: cluster,
            taxonNames: study.expressed_taxon_names,
            inferCNVIdeogramFiles: ideogram_files,
            bamBundleList: bam_bundle_list,
            uniqueGenes: study.unique_genes,
            geneLists: precomputed_scores,
            precomputedHeatmapLabel: study.default_options[:precomputed_heatmap_label],
            annotationList: AnnotationVizService.get_study_annotation_options(study, user),
            clusterGroupNames: ClusterVizService.load_cluster_group_options(study),
            spatialGroups: spatial_group_options,
            differentialExpression: AnnotationVizService.differential_expression_menu_opts(study),
            hasImageCache: study.cluster_groups.where(has_image_cache: true).pluck(:name),
            imageFiles: image_options,
            clusterPointAlpha: study.default_cluster_point_alpha,
            colorProfile: study.default_color_profile,
            bucketId: study.bucket_id
          }
        end
      end

    end
  end
end
