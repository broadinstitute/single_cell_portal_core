module Api
  module V1
    module Visualization
      # API methods for visualizing annotation-related data
      # does NOT contain methods for editing annotations
      class AnnotationsController < ApiBaseController
        include Concerns::ApiCaching
        include Swagger::Blocks

        VALID_SCOPE_VALUES = ['study', 'cluster']
        VALID_TYPE_VALUES = ['group', 'numeric']

        before_action :set_current_api_user!
        before_action :set_study
        before_action :check_study_view_permission
        # don't cache the annotation list, since it is user dependent
        before_action :check_api_cache!, except: :index
        after_action :write_api_cache!, except: :index

        annotation_description_doc = 'Object with name (String), values (Array of unique values), type (String), scope (String), and cluster_name (string, if applicable)'

        swagger_path '/studies/{accession}/annotations' do
          operation :get do
            key :tags, [
                'Visualization'
            ]
            key :summary, 'Get all annotations for the study'
            key :description, 'Get all annotations for the study, with name, values, type, scope, and cluster_name if applicable'
            key :operationId, 'study_annotations_path'
            parameter({
              name: :accession,
              in: :path,
              description: 'Study accession number (e.g. SCPXXX)',
              required: true,
              type: :string
            })
            response 200 do
              key :description, 'Array of Annotation objects'
              schema do
                key :type, :array
                key :title, 'Array'
                items do
                  key :title, 'Annotation'
                  key :description, annotation_description_doc
                end
              end
            end
            extend SwaggerResponses::StudyControllerResponses
          end
        end

        def index
          render json: AnnotationVizService.available_annotations(@study, cluster: nil, current_user: current_api_user)
        end

        swagger_path '/studies/{accession}/annotations/{annotation_name}' do
          operation :get do
            key :tags, [
                'Visualization'
            ]
            key :summary, 'Get an annotation for a study'
            key :description, 'Get a single annotation object'
            key :operationId, 'study_annotation_path'

            parameter do
              key :name, :accession
              key :in, :path
              key :description, 'Study accession number (e.g. SCPXXX)'
              key :required, true
              key :type, :string
            end
            parameter do
              key :name, :annotation_name
              key :in, :path
              key :description, 'Name of annotation'
              key :required, true
              key :type, :string
            end
            parameter do
              key :name, :annotation_type
              key :in, :query
              key :description, 'Type of annotation. One of "group" or "numeric".'
              key :type, :string
              key :enum, VALID_TYPE_VALUES
            end
            parameter do
              key :name, :annotation_scope
              key :in, :query
              key :description, 'Scope of annotation.  One of "study" or "cluster".'
              key :type, :string
              key :enum, VALID_SCOPE_VALUES
            end
            response 200 do
              key :description, annotation_description_doc
            end
            extend SwaggerResponses::StudyControllerResponses
          end
        end

        def show
          annotation = self.class.get_selected_annotation(@study, params)
          render json: annotation
        end

        swagger_path '/studies/{accession}/annotations/{annotation_name}/cell_values' do
          operation :get do
            key :tags, [
                'Visualization'
            ]
            key :summary, 'Get cell values for an annotation for a study'
            key :description, 'Get cell values for an annotation object.  Useful for e.g. dot plots.'
            key :operationId, 'study_annotation_cell_values_path'
            parameter do
              key :name, :accession
              key :in, :path
              key :description, 'Study accession number (e.g. SCPXXX)'
              key :required, true
              key :type, :string
            end
            parameter do
              key :name, :annotation_name
              key :in, :path
              key :description, 'Name of annotation'
              key :required, true
              key :type, :string
            end
            parameter do
              key :name, :annotation_type
              key :in, :query
              key :description, 'Type of annotation. One of "group" or "numeric".'
              key :type, :string
              key :enum, VALID_TYPE_VALUES
            end
            parameter do
              key :name, :annotation_scope
              key :in, :query
              key :description, 'Scope of annotation.  One of "study" or "cluster".'
              key :type, :string
              key :enum, VALID_SCOPE_VALUES
            end
            response 200 do
              key :description, '2-column TSV of cell names and their values for the requested annotation.  Column headers are NAME (the cell name) and the name of the returned annotation'
            end
            extend SwaggerResponses::StudyControllerResponses
          end
        end

        def cell_values
          annotation = self.class.get_selected_annotation(@study, params)
          cell_cluster = @study.cluster_groups.by_name(params[:cluster])
          if cell_cluster.nil?
            cell_cluster = @study.default_cluster
          end

          render plain: AnnotationVizService.annotation_cell_values_tsv(@study, cell_cluster, annotation)
        end

        swagger_path '/studies/{accession}/annotations/facets' do
          operation :get do
            key :tags, [
              'Visualization'
            ]
            key :summary, 'Get facet assignments for a cluster'
            key :description, 'Get annotation assignments (i.e. facets) for specified cells from a cluster. ' \
                              'Only applicable to full resolution data (i.e. all cells)'
            key :operationId, 'study_annotation_facets_path'
            parameter do
              key :name, :accession
              key :in, :path
              key :description, 'Study accession number'
              key :example, 'SCP1234'
              key :required, true
              key :type, :string
            end
            parameter do
              key :name, :annotations
              key :in, :query
              key :description, 'List of annotations'
              key :example, 'cell_type__ontology_label--group--study,disease__ontology_label'
              key :required, true
              key :type, :string
            end
            parameter do
              key :name, :cluster
              key :in, :query
              key :description, 'Name of requested cluster'
              key :type, :string
              key :required, true
            end
            response 200 do
              key :description, 'Array of integer-based annotation assignments for all cells in requested cluster'
              schema do
                key :title, 'Annotations'
                property :cells do
                  key :type, :array
                  key :description, 'Array of arrays of integer assignments of each cell for all requested annotations'
                  items do
                    key :type, :array
                    key :example, [[0, 0], [0, 1], [1, 2], [2, 2], [2, 0]]
                    items do
                      key :type, :integer
                      key :minItems, 2
                    end
                  end
                end
                property :facets do
                  key :type, :array
                  key :minItems, 2
                  key :example, [
                    {
                      annotation: 'cell_type__ontology_label--group--study',
                      groups: %w[eosinophil macrophage lymphocyte]
                    },
                    {
                      annotation: 'disease__ontology_label--group--study',
                      groups: ['Crohn disease', 'acute myeloid leukemia', 'chronic lymphocytic leukemia']
                    }
                  ].as_json
                  items do
                    key :type, :object
                    property :annotation do
                      key :type, :string
                      key :description, 'Annotation identifier'
                    end
                    property :groups do
                      key :type, :array
                      key :description, 'List of unique values for requested annotation'
                      key :example, "['eosinophil', 'macrophage', 'lymphocyte']"
                      items do
                        key :type, :string
                      end
                    end
                  end
                end
              end
            end
            extend SwaggerResponses::StudyControllerResponses
          end
        end

        def facets
          cluster = ClusterVizService.get_cluster_group(@study, params)
          if cluster.nil?
            render json: { error: "Cannot find cluster: #{params[:cluster]}" }, status: :not_found and return
          end

          # need to check for presence as some clusters will not have them if cells were not found in all_cells_array
          unless cluster.indexed
            render json: { error: 'Cluster is not indexed' }, status: :bad_request and return
          end

          if params[:annotations].include?('--numeric--')
            render json: { error: 'Cannot use numeric annotations for facets' }, status: :bad_request and return
          end

          annotations = self.class.get_facet_annotations(@study, cluster, params[:annotations])
          missing = self.class.find_missing_annotations(annotations, params[:annotations])
          if missing.any?
            render json: { error: "Cannot find annotations: #{missing.join(', ')}" }, status: :not_found and return
          end

          # use new cell index arrays to load data much faster
          indexed_cluster_cells = cluster.cell_index_array
          annotation_arrays = {}
          facets = []
          # build arrays of annotation values, and populate facets response array
          annotations.each do |annotation|
            scope = annotation[:scope]
            identifier = annotation[:identifier]

            data_obj = scope == 'study' ? @study.cell_metadata.by_name_and_type(annotation[:name], 'group') : cluster
            study_file_id = scope == 'study' ? @study.metadata_file.id : cluster.study_file_id
            array_query = {
              name: annotation[:name], array_type: 'annotations', linear_data_type: data_obj.class.name,
              linear_data_id: data_obj.id, study_id: @study.id, study_file_id:
            }
            annotation_arrays[identifier] = DataArray.concatenate_arrays(array_query)
            facets << { annotation: identifier, groups: annotation[:values] }
          end

          # iterate through indexed_cluster_cells to compute annotation value indices
          # value => current entry from indexed_cluster_cells
          # index => current position, will also be index of original cell name from cluster_cells
          cells = indexed_cluster_cells.map.with_index do |value, index|
            facets.map do |facet|
              annotation = facet[:annotation]
              scope = annotation.split('--').last
              if scope == 'study'
                label = annotation_arrays[annotation][value] || '--Unspecified--'
              else
                label = annotation_arrays[annotation][index] || '--Unspecified--'
              end
              facet[:groups].index(label)
            end
          end

          render json: { cells:, facets: }
        end

        swagger_path '/studies/{accession}/annotations/gene_lists/{gene_list}' do
          operation :get do
            key :tags, [
              'Visualization'
            ]
            key :summary, 'Get column values for an gene list for a study'
            key :description, 'Get column values for a gene list.  Useful for heatmaps.'
            key :operationId, 'study_annotation_gene_list_path'
            parameter do
              key :name, :accession
              key :in, :path
              key :description, 'Study accession number (e.g. SCPXXX)'
              key :required, true
              key :type, :string
            end
            parameter do
              key :name, :gene_list
              key :in, :path
              key :description, 'Name of gene list'
              key :required, true
              key :type, :string
            end
            response 200 do
              key :description, '2-column TSV of column header names from the gene list file.  Column headers are NAME (the cell name) and the name of the gene list'
            end
            extend SwaggerResponses::StudyControllerResponses
          end
        end

        def gene_list
          gene_list = @study.precomputed_scores.by_name(params[:gene_list])
          render plain: gene_list.cluster_values_tsv
        end

        # parses the url params to identify the selected cluster
        def self.get_selected_annotation(study, params)
          annot_params = get_annotation_params(params)
          if annot_params[:name] == '_default'
            annot_params[:name] = nil
          end
          cluster = nil
          if annot_params[:scope] == 'cluster'
            if params[:cluster].blank?
              render(json: {error: 'You must specify the cluster for cluster-scoped annotations'}, status: 404) and return
            end
            cluster = study.cluster_groups.by_name(params[:cluster])
          end
          AnnotationVizService.get_selected_annotation(study,
                                                       cluster: cluster,
                                                       annot_name: annot_params[:name],
                                                       annot_type: annot_params[:type],
                                                       annot_scope: annot_params[:scope])
        end

        def self.get_facet_annotations(study, cluster, annot_param)
          annotations = annot_param.split(',').map { |annot| convert_annotation_param(annot) }
          annotations.map do |annotation|
            AnnotationVizService.get_selected_annotation(study, cluster:, fallback: false, **annotation)
          end.compact
        end

        def self.convert_annotation_param(annotation_param)
          annot_name, annot_type, annot_scope = annotation_param.split('--')
          { annot_name:, annot_type:, annot_scope: }
        end

        # parses url params into an object with name, type, and scope keys
        def self.get_annotation_params(url_params)
          {
            name: url_params[:annotation_name].blank? ? nil : url_params[:annotation_name],
            type: url_params[:annotation_type].blank? ? nil : url_params[:annotation_type],
            scope: url_params[:annotation_scope].blank? ? nil : url_params[:annotation_scope]
          }
        end

        def self.find_missing_annotations(annotations, requested)
          requested.split(',').reject { |id| annotations.detect { |annot| annot[:identifier] == id } }
        end
      end
    end
  end
end
