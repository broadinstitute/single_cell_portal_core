class AnnotationVizService
  # set of utility methods used for interacting with annotation data

  # global label for dealing with blank/nil group-based annotation values
  MISSING_VALUE_LABEL = '--Unspecified--'.freeze

  # Retrieves an object representing the selected annotation. If nil is passed for the last four
  # arguments, it will get the study's default annotation instead
  # Params:
  # - study: the Study object
  # - cluster: ClusterGroup object (or nil for study-wide annotations)
  # - annot_name: string name of the annotation
  # - annot_type: string type (group or numeric)
  # - annot_scope: string scope (study, cluster, or user)
  # Returns:
  # - See populate_annotation_by_class for the object structure
  def self.get_selected_annotation(study, cluster: nil, annot_name: nil, annot_type: nil, annot_scope: nil)
    # construct object based on name, type & scope
    if annot_name.blank?
      # get the default annotation
      default_annot = nil
      if annot_scope == 'study'
        # get the default study-wide annotation
        default_annot = study.default_annotation(nil)
      elsif cluster.present?
        # get the default annotation for the cluster
        default_annot = study.default_annotation(cluster)
      else
        # get the default annotation for the default cluster
        default_annot = study.default_annotation
      end

      if !default_annot.blank?
        annot_name, annot_type, annot_scope = default_annot.split('--')
        if cluster.blank?
          cluster = study.default_cluster
        end
      end
    end

    case annot_scope
    when 'cluster'
      annotation_source = cluster.cell_annotations.find {|ca| ca[:name] == annot_name && ca[:type] == annot_type}
      if annotation_source.nil?
        # if there's no match, default to the first annotation
        annotation_source = cluster.cell_annotations.first
      end
    when 'user'
      annotation_source = UserAnnotation.find(annot_name)
    else
      annotation_source = study.cell_metadata.by_name_and_type(annot_name, annot_type)
    end
    # rescue from an invalid annotation request by defaulting to the first cell metadatum present
    if annotation_source.nil?
      annotation_source = study.cell_metadata.first
    end
    populate_annotation_by_class(source: annotation_source, scope: annot_scope, type: annot_type)
  end

  # attempt to load an annotation based on instance class
  # Params:
  # - source: A ClusterGroup cell_annotation, a UserAnnotation, or a CellMetadatum object
  # Returns:
  # - {
  #     name: string name of annotation
  #     type: string type
  #     scope: string scope
  #     values: unique values for the annotation
  #     identifier: string in the form of "{name}--{type}--{scope}", suitable for frontend options selectors
  #   }
  def self.populate_annotation_by_class(source:, scope:, type:)
    if source.is_a?(CellMetadatum)
      annotation = {name: source.name, type: source.annotation_type,
                    scope: 'study', values: sanitize_values_array(source.values.to_a, type),
                    identifier: "#{source.name}--#{type}--#{scope}"}
    elsif source.is_a?(UserAnnotation)
      annotation = {name: source.name, type: type, scope: scope, values: sanitize_values_array(source.values.to_a, type),
                    identifier: "#{source.id}--#{type}--#{scope}", id: source.id}
    elsif source.is_a?(Hash)
      annotation = {name: source[:name], type: type, scope: scope, values: sanitize_values_array(source[:values].to_a, type),
                    identifier: "#{source[:name]}--#{type}--#{scope}"}
    end
    annotation
  end

  def self.get_study_annotation_options(study, user)
    subsample_thresholds = Hash[
      study.cluster_groups.map {|cluster| [cluster.name, ClusterVizService.subsampling_options(cluster)] }
    ]
    {
      default_cluster: study.default_cluster&.name,
      default_annotation: AnnotationVizService.get_selected_annotation(study),
      annotations: AnnotationVizService.available_annotations(study, cluster: nil, current_user: user),
      clusters: study.cluster_groups.pluck(:name),
      subsample_thresholds: subsample_thresholds
    }
  end

  # convert a UserAnnotation object to a annotation of the type expected by the frontend
  def self.user_annot_to_annot(user_annotation, cluster)
    {
      name: user_annotation.name,
      id: user_annotation.id.to_s,
      type: 'group', # all user annotations are group
      values: sanitize_values_array(user_annotation.values, 'group'),
      scope: 'user',
      cluster_name: cluster.name
    }
  end

  # returns a flat array of annotation objects, with name, scope, annotation_type, and values for each
  def self.available_annotations(study, cluster: nil, current_user: nil, annotation_type: nil)
    annotations = []
    metadata_annots = available_metadata_annotations(study, annotation_type: annotation_type)
    annotations.concat(metadata_annots)
    cluster_annots = []
    if cluster.present?
      cluster_annots = ClusterVizService.available_annotations_by_cluster(cluster, annotation_type)
      if current_user.present?
        cluster_annots.concat(UserAnnotation.viewable_by_cluster(current_user, cluster)
                                            .map{ |ua| AnnotationVizService.user_annot_to_annot(ua, cluster) })
      end
    else
      study.cluster_groups.each do |cluster_group|
        cluster_annots.concat(ClusterVizService.available_annotations_by_cluster(cluster_group, annotation_type))
        if current_user.present?
          cluster_annots.concat(UserAnnotation.viewable_by_cluster(current_user, cluster_group)
                                              .map{ |ua| AnnotationVizService.user_annot_to_annot(ua, cluster_group) })
        end
      end
    end
    annotations.concat(cluster_annots)
    annotations
  end

  # helper method to efficiently list out metadata annotations classed as valid/invalid for visualization
  def self.available_metadata_annotations(study, annotation_type: nil)
    # get all the metadata in a single query
    all_metadata = study.cell_metadata.to_a
    all_names = all_metadata.map(&:name)
    all_metadata.map do |annot|
      # viewable if the type is numeric or there's no corresponding label and it's within the range of visualization values
      is_viewable = annot.annotation_type == 'numeric' ||
        study.override_viz_limit_annotations.include?(annot.name) ||
        all_names.exclude?(annot.name + '__ontology_label') &&
        CellMetadatum::GROUP_VIZ_THRESHOLD === annot.values.size
      annot_values_array = annot.values
      if study.override_viz_limit_annotations.include?(annot.name) && annot_values_array.length == 0
        # we need to dynamically build the array
        annot_values_array = annot.concatenate_data_arrays(annot.name, 'annotations').uniq
      end
      {
        name: annot.name,
        type: annot.annotation_type,
        values: sanitize_values_array(annot_values_array, annot.annotation_type),
        scope: is_viewable ? 'study' : 'invalid',
        is_differential_expression_enabled: annot.is_differential_expression_enabled
      }
    end
  end

  def self.annotation_cell_values_tsv(study, cluster, annotation)
    cells = cluster.concatenate_data_arrays('text', 'cells')
    if annotation[:scope] == 'cluster'
      annotations = cluster.concatenate_data_arrays(annotation[:name], 'annotations')
    else
      study_annotations = study.cell_metadata_values(annotation[:name], annotation[:type])
      annotations = []
      cells.each do |cell|
        annotation_value = study_annotations[cell]
        annotations << annotation_value
      end
    end
    # sanitize annotation values
    sanitized_annotations = AnnotationVizService.sanitize_values_array(annotations, annotation[:type])
    # assemble rows of data
    rows = []
    cells.each_with_index do |cell, index|
      rows << [cell, sanitized_annotations[index]].join("\t")
    end
    headers = ['NAME', annotation[:name]]
    [headers.join("\t"), rows.join("\n")].join("\n")
  end

  # sanitizes an array of values to replace blank/missing values with a pre-defined label
  # prevents breaking various kinds of visualization due to values not being defined
  #
  # * *params*
  #   - +value+ (Array) => values array to sanitize
  #   - +annotation_type+ (String) => type of array, either "group" or "numeric"
  #
  # * *returns*
  #   - (Array) => sanitized output array if "group", otherwise input array
  def self.sanitize_values_array(values, annotation_type)
    return values if annotation_type == 'numeric'
    values.map {|value| value.blank? ? MISSING_VALUE_LABEL : value }
  end

  # create a menu configuration for differential expression results for a given study
  def self.differential_expression_menu_opts(study)
    study.differential_expression_results.map do |diff_exp_result|
      {
        cluster_name: diff_exp_result.cluster_group&.name,
        annotation_name: diff_exp_result.annotation_name,
        annotation_scope: diff_exp_result.annotation_scope,
        select_options: diff_exp_result.select_options
      }
    end
  end
end
