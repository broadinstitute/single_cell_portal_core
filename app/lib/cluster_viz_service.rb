class ClusterVizService
  # set of utility methods used for visualizing cluster data

  def self.get_cluster_group(study, params)
    # determine which URL param to use for selection
    selector = params[:cluster].nil? ? params[:gene_set_cluster] : params[:cluster]
    if selector.nil? || selector.empty?
      study.default_cluster
    else
      study.cluster_groups.by_name(selector)
    end
  end

  # helper method to load all possible cluster groups for a study
  def self.load_cluster_group_options(study)
    non_spatial_file_ids = study.clustering_files.where(is_spatial: false).pluck(:id)
    ClusterGroup.where(study: study, :study_file_id.in => non_spatial_file_ids).pluck(:name)
  end

  # helper method to load all available cluster_group-specific annotations
  def self.load_cluster_group_annotations(study, cluster, current_user)
    grouped_options = study.formatted_annotation_select(cluster: cluster)
    # load available user annotations (if any)
    if current_user.present?
      user_annotations = UserAnnotation.viewable_by_cluster(current_user, cluster)
      unless user_annotations.empty?
        grouped_options['User Annotations'] = user_annotations.map {|annot| ["#{annot.name}", "#{annot.id}--group--user"] }
      end
    end
    grouped_options
  end


  def self.available_annotations_by_cluster(cluster, annotation_type=nil)
    cluster.cell_annotations_by_type(annotation_type).map do |annot|
      {
        name: annot[:name],
        type: annot[:type],
        values: annot[:values],
        # mark non-plottable annotations as 'invalid' so they show up in the dropdown but are not selectable
        scope: cluster.can_visualize_cell_annotation?(annot) ? 'cluster' : 'invalid',
        cluster_name: cluster.name,
        is_differential_expression_enabled: annot[:is_differential_expression_enabled]
      }
    end
  end

  # helper method to load spatial coordinate group names
  # return an array of hashes with spatial file names and associated_clusters  specified, where associated_clusters is the names of
  # the clusters
  def self.load_spatial_options(study)
    # grab all the spatial files for this study
    spatial_file_info = study.clustering_files.where(is_spatial: true).pluck(:name, :spatial_cluster_associations)
    # now grab any non spatial cluster files for the study that had ids specified in the spatial_cluster_associations above
    # and put them in an id=>name hash
    associated_clusters = StudyFile.where(study: study, :id.in => spatial_file_info.map{ |si| si[1] }.flatten.uniq)
                                   .pluck(:id, :name)
                                   .map{ |a| [a[0].to_s, a[1]] }.to_h
    # now return an array of objects with names and associated cluster names
    spatial_file_info.map do |cluster|
      associated_cluster_names = cluster[1].map{ |id| associated_clusters[id] }
      { name: cluster[0], associated_clusters: associated_cluster_names }
    end
  end

  def self.load_image_options(study)
    # grab all the image files for this study
    attrs = [:name, :spatial_cluster_associations, :upload_file_name, :description]
    image_file_info = ActiveRecordUtils.pluck_to_hash(StudyFile.where(study: study, file_type: 'Image'), attrs)

    associated_cluster_ids = image_file_info.map{ |si| si[:spatial_cluster_associations] }.flatten.uniq
    # now grab any non spatial cluster files for the study that had ids specified in the image files above
    # and put them in an id=>name hash
    associated_clusters = StudyFile.where(study: study, :id.in => associated_cluster_ids)
                                   .pluck(:id, :name)
                                   .map{ |a| [a[0].to_s, a[1]] }.to_h
    # now return an array of objects with names and associated cluster names
    image_file_info.map do |file|
      associated_cluster_names = file[:spatial_cluster_associations].map{ |id| associated_clusters[id] }
      { name: file[:name],
        associated_clusters: associated_cluster_names.compact,
        bucket_file_name: file[:upload_file_name],
        description: file[:description] }
    end
  end


  # return an array of values to use for subsampling dropdown scaled to number of cells in study
  # only options allowed are 1000, 10000, 20000, and 100000
  # will only provide options if subsampling has completed for a cluster
  def self.subsampling_options(cluster)
    return [] if cluster.nil? || cluster.is_subsampling?

    ClusterGroup::SUBSAMPLE_THRESHOLDS.select { |sample| sample < cluster.points }
  end

  # return an array of values to use for subsampling dropdown scaled to number of cells in study
  # only options allowed are 1000, 10000, 20000, and 100000
  # will only provide options if subsampling has completed for a cluster
  def self.default_subsampling(cluster)
    return nil if cluster.nil? || cluster.points < 100000

    ClusterGroup::SUBSAMPLE_THRESHOLDS.select { |val| val <= ClusterGroup::MAX_THRESHOLD }.max
  end

    # load custom coordinate-based annotation labels for a given cluster
  def self.load_cluster_group_coordinate_labels(cluster)
    annotations = []
    return annotations if cluster.nil?

    # assemble source data
    x_array = cluster.concatenate_data_arrays('x', 'labels')
    y_array = cluster.concatenate_data_arrays('y', 'labels')
    z_array = cluster.concatenate_data_arrays('z', 'labels')
    text_array = cluster.concatenate_data_arrays('text', 'labels')

    # iterate through list of data objects to construct necessary annotations
    x_array.each_with_index do |point, index|
      annot = {
        showarrow: false,
        x: point,
        y: y_array[index],

        text: text_array[index],
        font: {
          family: cluster.coordinate_labels_options[:font_family],
          size: cluster.coordinate_labels_options[:font_size],
          color: cluster.coordinate_labels_options[:font_color]
        }
      }
      if cluster.is_3d?
        annot[:z] = z_array[index]
      end
      annotations << annot
    end
    annotations
  end

  # retrieve axis labels from cluster coordinates file (if provided)
  def self.load_axis_labels(cluster)
    coordinates_file = cluster.study_file
    {
        x: coordinates_file.x_axis_label.blank? ? 'X' : coordinates_file.x_axis_label,
        y: coordinates_file.y_axis_label.blank? ? 'Y' : coordinates_file.y_axis_label,
        z: coordinates_file.z_axis_label.blank? ? 'Z' : coordinates_file.z_axis_label
    }
  end

  # compute the aspect ratio between all ranges and use to enforce equal-aspect ranges on 3d plots
  def self.compute_aspect_ratios(range)
    # determine largest range for computing aspect ratio
    extent = {}
    return { mode: 'manual' } if range.blank?

    range.each.map { |axis, domain| extent[axis] = domain.first.upto(domain.last).size - 1 }
    largest_range = extent.values.max

    # now compute aspect mode and ratios
    aspect = {
        mode: extent.values.uniq.size == 1 ? 'cube' : 'manual'
    }
    range.each_key do |axis|
      aspect[axis.to_sym] = extent[axis].to_f / largest_range
    end
    aspect
  end

  # generic method to populate data structure to render a cluster scatter plot
  # uses cluster_group model and loads annotation for both group & numeric plots
  # data values are pulled from associated data_array entries for each axis and annotation/text value
  def self.load_cluster_group_data_array_points(study, cluster, annotation, subsample_threshold=nil, include_coords: true, include_cells: true, include_annotations: true)
    # construct annotation key to load subsample data_arrays if needed, will be identical to params[:annotation]
    subsample_annotation = "#{annotation[:name]}--#{annotation[:type]}--#{annotation[:scope]}"
    return {} if cluster.nil?

    x_array = []
    y_array = []
    z_array = []
    cells = []

    data_source = cluster
    if annotation[:scope] == 'user'
      user_annotation = UserAnnotation.find(annotation[:id])
      return {} if user_annotation.nil?

      subsample_annotation = user_annotation.formatted_annotation_identifier
      data_source = user_annotation
    end
    if include_coords
      x_array = data_source.concatenate_data_arrays('x', 'coordinates', subsample_threshold, subsample_annotation)
      y_array = data_source.concatenate_data_arrays('y', 'coordinates', subsample_threshold, subsample_annotation)
      z_array = data_source.concatenate_data_arrays('z', 'coordinates', subsample_threshold, subsample_annotation)
    end
    if include_cells || annotation[:scope] == 'study'
      # for study annotations, we have to grab the cluster cells to match with the study-wide annotation
      cells = data_source.concatenate_data_arrays('text', 'cells', subsample_threshold, subsample_annotation)
    end

    viz_data = {}
    if include_annotations
      annotation_array = get_annotation_values_array(study, cluster, annotation, cells, subsample_annotation, subsample_threshold)
      viz_data = { annotations: annotation_array }
    end

    if include_cells
      viz_data[:cells] = cells
    end

    if include_coords
      viz_data[:x] = x_array
      viz_data[:y] = y_array
      if cluster.is_3d?
        viz_data[:z] = z_array
      end
    end

    viz_data
  end


  # returns an array of the values for the given annotation, sorted by the cells of the given cells array
  def self.get_annotation_values_array(study, cluster, annotation, cells, subsample_annotation, subsample_threshold)
    return [] if study.nil? || cluster.nil?

    # Construct the arrays based on scope
    case annotation[:scope]
    when 'cluster'
      annotation_array = cluster.concatenate_data_arrays(annotation[:name], 'annotations', subsample_threshold, subsample_annotation)
    when 'user'
      # for user annotations, we have to load by id as names may not be unique to clusters
      user_annotation = UserAnnotation.find(annotation[:id])
      return [] if user_annotation.nil?

      subsample_annotation = user_annotation.formatted_annotation_identifier
      annotation_array = user_annotation.concatenate_data_arrays(annotation[:name], 'annotations', subsample_threshold, subsample_annotation)
    else
      # for study-wide annotations, load from study_metadata values instead of cluster-specific annotations
      metadata_obj = study.cell_metadata.by_name_and_type(annotation[:name], annotation[:type])
      annotation_hash = metadata_obj&.cell_annotations || {}
      annotation_array = cells&.map { |cell| annotation_hash[cell] } || []
    end
    AnnotationVizService.sanitize_values_array(annotation_array, annotation[:type])
  end

  # validate study has raw counts, and that all cells from the cluster file exist in a single raw counts matrix
  #
  # * *params*
  #   - +study+   (Study) => Study to which StudyFile belongs
  #   - +cluster+ (ClusterGroup) => Clustering object to source cell names from
  #
  # * *returns*
  #   - (StudyFile) => Corresponding raw counts file
  #
  # * *raises*
  #   - (ArgumentError) => if requested parameters do not validate
  def self.raw_matrix_for_cluster_cells(study, cluster)
    raw_counts_matrices = StudyFile.where(study_id: study.id,
                                          parse_status: 'parsed',
                                          queued_for_deletion: false,
                                          'expression_file_info.is_raw_counts' => true)
    raise ArgumentError, "#{study.accession} has no parsed raw counts data" if raw_counts_matrices.empty?

    cluster_cells = cluster.concatenate_data_arrays('text', 'cells')
    # if the intersection of cluster_cells and matrix_cells is complete, then this will return a matrix file
    raw_matrix = raw_counts_matrices.detect do |matrix|
      matrix_cells = study.expression_matrix_cells(matrix)
      (cluster_cells & matrix_cells) == cluster_cells
    end
    raise ArgumentError, "#{cluster.name} does not have all cells in a single raw counts matrix" if raw_matrix.nil?

    if raw_matrix.file_type == 'MM Coordinate Matrix'
      raise ArgumentError, "#{raw_matrix.upload_file_name} is missing required data" unless raw_matrix.has_completed_bundle?
    end

    raw_matrix
  end

  # find what annotation values are represented for this combination of cluster & annotation
  # primarily important as a validation for differential expression, as DE cannot be run on single-value annotations,
  # or on labels that have only one cell
  #
  # * *params*
  #   - +cluster+    (ClusterGroup) => Clustering object being used as control cell list
  #   - +annotation_name+  (String) => Name of requested annotation
  #   - +annotation_scope+ (String) => Scope of requested annotation ('study' or 'cluster')
  def self.cells_by_annotation_label(cluster, annotation_name, annotation_scope)
    study = cluster.study
    cells = cluster.concatenate_data_arrays('text', 'cells')
    annotation = { name: annotation_name, scope: annotation_scope, type: 'group' } # only valid for group-based
    labels = get_annotation_values_array(study, cluster, annotation, cells, nil, nil)
    cells_by_label = {}
    labels.each_with_index do |label, index|
      cells_by_label[label] ||= []
      cells_by_label[label] << cells[index]
    end
    cells_by_label
  end
end
