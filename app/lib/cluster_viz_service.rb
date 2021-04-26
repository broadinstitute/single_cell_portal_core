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
    non_spatial_file_ids = StudyFile.where(study: study, :is_spatial.ne => true, file_type: 'Cluster').pluck(:id)
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
        scope: 'cluster',
        cluster_name: cluster.name
      }
    end
  end

  # helper method to load spatial coordinate group names
  # return an array of hashes with spatial file names and associated_clusters  specified, where associated_clusters is the names of
  # the clusters
  def self.load_spatial_options(study)
    # grab all the spatial files for this study, and create a name=>associations hash
    spatial_file_info = StudyFile.where(study: study, is_spatial: true, file_type: 'Cluster')
                                 .pluck(:name, :spatial_cluster_associations).to_h
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

  # return an array of values to use for subsampling dropdown scaled to number of cells in study
  # only options allowed are 1000, 10000, 20000, and 100000
  # will only provide options if subsampling has completed for a cluster
  def self.subsampling_options(cluster)
    num_points = cluster.points
    if cluster.is_subsampling?
      []
    else
      ClusterGroup::SUBSAMPLE_THRESHOLDS.select {|sample| sample < num_points}
    end
  end

  # return an array of values to use for subsampling dropdown scaled to number of cells in study
  # only options allowed are 1000, 10000, 20000, and 100000
  # will only provide options if subsampling has completed for a cluster
  def self.default_subsampling(cluster)
    num_points = cluster.points
    if num_points < 10000
      return nil
    else
      ClusterGroup::SUBSAMPLE_THRESHOLDS.select{|val| val <= 10000}.max
    end
  end

  # Convert cluster group data array points into JSON plot data for Plotly
  def self.transform_coordinates(coordinates, study, cluster_group, selected_annotation)
    plot_data = []
    plot_type = cluster_group.is_3d? ? 'scatter3d' : 'scattergl'
    coordinates.sort_by {|k,v| k}.each_with_index do |(cluster, data), index|
      cluster_props = {
        x: data[:x],
        y: data[:y],
        cells: data[:cells],
        name: data[:name],
        type: plot_type,
        mode: 'markers',
        marker: data[:marker],
        opacity: study.default_cluster_point_alpha,
      }

      if !data[:annotations].nil?
        cluster_props[:annotations] = data[:annotations]
      end

      if cluster_group.is_3d?
        cluster_props[:z] = data[:z]
        cluster_props[:textposition] = 'bottom right'
      end

      plot_data.push(cluster_props)
    end

    plot_data
  end

    # load custom coordinate-based annotation labels for a given cluster
  def self.load_cluster_group_coordinate_labels(cluster)
    # assemble source data
    x_array = cluster.concatenate_data_arrays('x', 'labels')
    y_array = cluster.concatenate_data_arrays('y', 'labels')
    z_array = cluster.concatenate_data_arrays('z', 'labels')
    text_array = cluster.concatenate_data_arrays('text', 'labels')
    annotations = []
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
    range.each.map {|axis, domain| extent[axis] = domain.first.upto(domain.last).size - 1}
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

  # set the range for a plotly scatter, will default to data-defined if cluster hasn't defined its own ranges
  # dynamically determines range based on inputs & available axes
  def self.get_range(cluster, coordinate_data)
    # select coordinate axes from inputs
    domain_keys = [:x, :y, :z]
    range = Hash[domain_keys.zip]
    if cluster.has_range?
      # use study-provided range if available
      range = cluster.domain_ranges
    else
      # take the minmax of each domain across all groups, then the global minmax
      raw_values = []

      domain_keys.each do |domain|
        if coordinate_data[domain_key]
          domain_range = RequestUtils.get_minmax(coordinate_data[domain])
          # RequestUtils.get_minmax will discard NaN/nil values that were ingested
          # only add domain range to list if we have a valid minmax
          raw_values << domain_range if domain_range.any?
        end
      end
      aggregate_range = raw_values.flatten.minmax
      # add 2% padding to range
      padding = (aggregate_range.first - aggregate_range.last) * 0.02
      absolute_range = [aggregate_range.first + padding, aggregate_range.last - padding]
      range[:x] = absolute_range
      range[:y] = absolute_range
      range[:z] = absolute_range
    end
    range
  end

  # generic method to populate data structure to render a cluster scatter plot
  # uses cluster_group model and loads annotation for both group & numeric plots
  # data values are pulled from associated data_array entries for each axis and annotation/text value
  def self.load_cluster_group_data_array_points(study, cluster, annotation, subsample_threshold=nil, include_coords=true, include_cells=true)
    # construct annotation key to load subsample data_arrays if needed, will be identical to params[:annotation]
    subsample_annotation = "#{annotation[:name]}--#{annotation[:type]}--#{annotation[:scope]}"

    x_array = []
    y_array = []
    z_array = []
    cells = []

    if annotation[:scope] == 'user'
      user_annotation = UserAnnotation.find(annotation[:id])
      subsample_annotation = user_annotation.formatted_annotation_identifier
      annotation_array = user_annotation.concatenate_user_data_arrays(annotation[:name], 'annotations', subsample_threshold, subsample_annotation)
      if include_coords
        x_array = user_annotation.concatenate_user_data_arrays('x', 'coordinates', subsample_threshold, subsample_annotation)
        y_array = user_annotation.concatenate_user_data_arrays('y', 'coordinates', subsample_threshold, subsample_annotation)
        z_array = user_annotation.concatenate_user_data_arrays('z', 'coordinates', subsample_threshold, subsample_annotation)
      end
      cells = user_annotation.concatenate_user_data_arrays('text', 'cells', subsample_threshold, subsample_annotation)
    else
      if include_coords
        x_array = cluster.concatenate_data_arrays('x', 'coordinates', subsample_threshold, subsample_annotation)
        y_array = cluster.concatenate_data_arrays('y', 'coordinates', subsample_threshold, subsample_annotation)
        z_array = cluster.concatenate_data_arrays('z', 'coordinates', subsample_threshold, subsample_annotation)
      end
      if include_cells || annotation[:scope] == 'study'
        # for study annotations, we have to grab the cluster cells to match with the study-wide annotation
        cells = cluster.concatenate_data_arrays('text', 'cells', subsample_threshold, subsample_annotation)
      end
    end

    annotation_array = get_annotation_values_array(study, cluster, annotation, cells, subsample_annotation, subsample_threshold)

    viz_data = { annotations: annotation_array }
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

    if annotation[:type] == 'numeric'
      text_array = []
      color_array = []
      # account for NaN when computing min/max
      min, max = RequestUtils.get_minmax(annotation_array)
      viz_data[:annotationRange] = {max: max, min: min}
    end

    viz_data
  end

  # returns an array of the values for the given annotation, sorted by the cells of the given cells array
  def self.get_annotation_values_array(study, cluster, annotation, cells, subsample_annotation, subsample_threshold)
    annotation_array = []
    # Construct the arrays based on scope
    if annotation[:scope] == 'cluster'
      annotation_array = cluster.concatenate_data_arrays(annotation[:name], 'annotations', subsample_threshold, subsample_annotation)
    elsif annotation[:scope] == 'user'
      # for user annotations, we have to load by id as names may not be unique to clusters
      user_annotation = UserAnnotation.find(annotation[:id])
      subsample_annotation = user_annotation.formatted_annotation_identifier
      annotation_array = user_annotation.concatenate_user_data_arrays(annotation[:name], 'annotations', subsample_threshold, subsample_annotation)
    else
      # for study-wide annotations, load from study_metadata values instead of cluster-specific annotations
      metadata_obj = study.cell_metadata.by_name_and_type(annotation[:name], annotation[:type])
      annotation_hash = metadata_obj.cell_annotations
      annotation_array = cells.map { |cell| annotation_hash[cell] }
    end
    annotation_array = AnnotationVizService.sanitize_values_array(annotation_array, annotation[:type])
    annotation_array
  end
end
