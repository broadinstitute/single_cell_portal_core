class ExpressionRenderingService
  def self.get_global_expression_render_data(study,
                                             subsample,
                                             gene,
                                             cluster,
                                             selected_annotation,
                                             boxpoints,
                                             current_user)
    render_data = {}

    render_data[:y_axis_title] = load_expression_axis_title(study)
    if selected_annotation[:type] == 'group'
      render_data[:values] = load_expression_boxplot_data_array_scores(study, gene, cluster, selected_annotation, subsample)
      render_data[:values_jitter] = boxpoints
    else
      render_data[:values] = load_annotation_based_data_array_scatter(study, gene, cluster, selected_annotation, subsample, render_data[:y_axis_title])
    end
    render_data[:options] = load_cluster_group_options(study)
    render_data[:cluster_annotations] = load_cluster_group_annotations(study, cluster, current_user)
    render_data[:subsampling_options] = subsampling_options(cluster)

    render_data[:rendered_cluster] = cluster.name
    render_data[:rendered_annotation] = "#{selected_annotation[:name]}--#{selected_annotation[:type]}--#{selected_annotation[:scope]}"
    render_data[:rendered_subsample] = subsample
    render_data
  end


  def self.load_expression_axis_title(study)
    study.default_expression_label
  end

   # helper method to load all possible cluster groups for a study
  def self.load_cluster_group_options(study)
    study.cluster_groups.map(&:name)
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

  # load box plot scores from gene expression values using data array of cell names for given cluster
  def self.load_expression_boxplot_data_array_scores(study, gene, cluster, annotation, subsample_threshold=nil)
    # construct annotation key to load subsample data_arrays if needed, will be identical to params[:annotation]
    subsample_annotation = "#{annotation[:name]}--#{annotation[:type]}--#{annotation[:scope]}"
    values = initialize_plotly_objects_by_annotation(annotation)

    # grab all cells present in the cluster, and use as keys to load expression scores
    # if a cell is not present for the gene, score gets set as 0.0
    cells = cluster.concatenate_data_arrays('text', 'cells', subsample_threshold, subsample_annotation)
    if annotation[:scope] == 'cluster'
      # we can take a subsample of the same size for the annotations since the sort order is non-stochastic (i.e. the indices chosen are the same every time for all arrays)
      annotations = cluster.concatenate_data_arrays(annotation[:name], 'annotations', subsample_threshold, subsample_annotation)
      cells.each_with_index do |cell, index|
        values[annotations[index]][:y] << gene['scores'][cell].to_f.round(4)
      end
    elsif annotation[:scope] == 'user'
      # for user annotations, we have to load by id as names may not be unique to clusters
      user_annotation = UserAnnotation.find(annotation[:id])
      subsample_annotation = user_annotation.formatted_annotation_identifier
      annotations = user_annotation.concatenate_user_data_arrays(annotation[:name], 'annotations', subsample_threshold, subsample_annotation)
      cells = user_annotation.concatenate_user_data_arrays('text', 'cells', subsample_threshold, subsample_annotation)
      cells.each_with_index do |cell, index|
        values[annotations[index]][:y] << gene['scores'][cell].to_f.round(4)
      end
    else
      # since annotations are in a hash format, subsampling isn't necessary as we're going to retrieve values by key lookup
      annotations =  study.cell_metadata.by_name_and_type(annotation[:name], annotation[:type]).cell_annotations
      cells.each do |cell|
        val = annotations[cell]
        # must check if key exists
        if values.has_key?(val)
          values[annotations[cell]][:y] << gene['scores'][cell].to_f.round(4)
          values[annotations[cell]][:cells] << cell
        end
      end
    end
    # remove any empty values as annotations may have created keys that don't exist in cluster
    values.delete_if {|key, data| data[:y].empty?}
    values
  end

  # method to load a 2-d scatter of selected numeric annotation vs. gene expression
  def self.load_annotation_based_data_array_scatter(study, gene, cluster, annotation, subsample_threshold, y_axis_title)

    # construct annotation key to load subsample data_arrays if needed, will be identical to params[:annotation]
    subsample_annotation = "#{annotation[:name]}--#{annotation[:type]}--#{annotation[:scope]}"
    cells = cluster.concatenate_data_arrays('text', 'cells', subsample_threshold, subsample_annotation)
    annotation_array = []
    annotation_hash = {}
    if annotation[:scope] == 'cluster'
      annotation_array = cluster.concatenate_data_arrays(annotation[:name], 'annotations', subsample_threshold, subsample_annotation)
    elsif annotation[:scope] == 'user'
      # for user annotations, we have to load by id as names may not be unique to clusters
      user_annotation = UserAnnotation.find(annotation[:id])
      subsample_annotation = user_annotation.formatted_annotation_identifier
      annotation_array = user_annotation.concatenate_user_data_arrays(annotation[:name], 'annotations', subsample_threshold, subsample_annotation)
      cells = user_annotation.concatenate_user_data_arrays('text', 'cells', subsample_threshold, subsample_annotation)
    else
      # for study-wide annotations, load from study_metadata values instead of cluster-specific annotations
      metadata_obj = study.cell_metadata.by_name_and_type(annotation[:name], annotation[:type])
      annotation_hash = metadata_obj.cell_annotations
    end
    values = {}
    values[:all] = {x: [], y: [], cells: [], annotations: [], text: [], marker: {size: study.default_cluster_point_size,
                                                                                 line: { color: 'rgb(40,40,40)', width: study.show_cluster_point_borders? ? 0.5 : 0}}}
    if annotation[:scope] == 'cluster' || annotation[:scope] == 'user'
      annotation_array.each_with_index do |annot, index|
        annotation_value = annot
        cell_name = cells[index]
        expression_value = gene['scores'][cell_name].to_f.round(4)

        values[:all][:text] << "<b>#{cell_name}</b><br>#{annotation_value}<br>#{y_axis_title}: #{expression_value}"
        values[:all][:annotations] << annotation_value
        values[:all][:x] << annotation_value
        values[:all][:y] << expression_value
        values[:all][:cells] << cell_name
      end
    else
      cells.each do |cell|
        if annotation_hash.has_key?(cell)
          annotation_value = annotation_hash[cell]
          expression_value = gene['scores'][cell].to_f.round(4)
          values[:all][:text] << "<b>#{cell}</b><br>#{annotation_value}<br>#{y_axis_title}: #{expression_value}"
          values[:all][:annotations] << annotation_value
          values[:all][:x] << annotation_value
          values[:all][:y] << expression_value
          values[:all][:cells] << cell
        end
      end
    end
    values
  end

  # method to initialize containers for plotly by annotation values
  def self.initialize_plotly_objects_by_annotation(annotation)
    values = {}
    annotation[:values].each do |value|
      values["#{value}"] = {y: [], cells: [], annotations: [], name: "#{value}" }
    end
    values
  end

  # return an array of values to use for subsampling dropdown scaled to number of cells in study
  # only options allowed are 1000, 10000, 20000, and 100000
  # will only provide options if subsampling has completed for a cluster
  def self.subsampling_options(cluster)
    if cluster.is_subsampling?
      []
    else
      ClusterGroup::SUBSAMPLE_THRESHOLDS.select {|sample| sample < cluster.points}
    end
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
      annotations << {
        showarrow: false,
        x: point,
        y: y_array[index],
        z: z_array[index],
        text: text_array[index],
        font: {
          family: cluster.coordinate_labels_options[:font_family],
          size: cluster.coordinate_labels_options[:font_size],
          color: cluster.coordinate_labels_options[:font_color]
        }
      }
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
  def self.set_range(inputs)
    # select coordinate axes from inputs
    domain_keys = inputs.map(&:keys).flatten.uniq.select {|i| [:x, :y, :z].include?(i)}
    range = Hash[domain_keys.zip]
    if @cluster.has_range?
      # use study-provided range if available
      range = @cluster.domain_ranges
    else
      # take the minmax of each domain across all groups, then the global minmax
      @vals = inputs.map {|v| domain_keys.map {|k| RequestUtils.get_minmax(v[k])}}.flatten.minmax
      # add 2% padding to range
      scope = (@vals.first - @vals.last) * 0.02
      raw_range = [@vals.first + scope, @vals.last - scope]
      range[:x] = raw_range
      range[:y] = raw_range
      range[:z] = raw_range
    end
    range
  end

  # generic method to populate data structure to render a cluster scatter plot
  # uses cluster_group model and loads annotation for both group & numeric plots
  # data values are pulled from associated data_array entries for each axis and annotation/text value
  def self.load_cluster_group_data_array_points(study, cluster, annotation, subsample_threshold=nil)
    # construct annotation key to load subsample data_arrays if needed, will be identical to params[:annotation]
    subsample_annotation = "#{annotation[:name]}--#{annotation[:type]}--#{annotation[:scope]}"
    x_array = cluster.concatenate_data_arrays('x', 'coordinates', subsample_threshold, subsample_annotation)
    y_array = cluster.concatenate_data_arrays('y', 'coordinates', subsample_threshold, subsample_annotation)
    z_array = cluster.concatenate_data_arrays('z', 'coordinates', subsample_threshold, subsample_annotation)
    cells = cluster.concatenate_data_arrays('text', 'cells', subsample_threshold, subsample_annotation)
    annotation_array = []
    annotation_hash = {}
    # Construct the arrays based on scope
    if annotation[:scope] == 'cluster'
      annotation_array = cluster.concatenate_data_arrays(annotation[:name], 'annotations', subsample_threshold, subsample_annotation)
    elsif annotation[:scope] == 'user'
      # for user annotations, we have to load by id as names may not be unique to clusters
      user_annotation = UserAnnotation.find(annotation[:id])
      subsample_annotation = user_annotation.formatted_annotation_identifier
      annotation_array = user_annotation.concatenate_user_data_arrays(annotation[:name], 'annotations', subsample_threshold, subsample_annotation)
      x_array = user_annotation.concatenate_user_data_arrays('x', 'coordinates', subsample_threshold, subsample_annotation)
      y_array = user_annotation.concatenate_user_data_arrays('y', 'coordinates', subsample_threshold, subsample_annotation)
      z_array = user_annotation.concatenate_user_data_arrays('z', 'coordinates', subsample_threshold, subsample_annotation)
      cells = user_annotation.concatenate_user_data_arrays('text', 'cells', subsample_threshold, subsample_annotation)
    else
      # for study-wide annotations, load from study_metadata values instead of cluster-specific annotations
      metadata_obj = study.cell_metadata.by_name_and_type(annotation[:name], annotation[:type])
      annotation_hash = metadata_obj.cell_annotations
      annotation[:values] = annotation_hash.values
    end
    coordinates = {}
    if annotation[:type] == 'numeric'
      text_array = []
      color_array = []
      # load text & color value from correct object depending on annotation scope
      cells.each_with_index do |cell, index|
        if annotation[:scope] == 'cluster'
          val = annotation_array[index]
          text_array << "#{cell}: (#{val})"
        else
          val = annotation_hash[cell]
          text_array <<  "#{cell}: (#{val})"
          color_array << val
        end
      end
      # if we didn't assign anything to the color array, we know the annotation_array is good to use
      color_array.empty? ? color_array = annotation_array : nil
      # account for NaN when computing min/max
      min, max = RequestUtils.get_minmax(annotation_array)
      coordinates[:all] = {
          x: x_array,
          y: y_array,
          annotations: annotation[:scope] == 'cluster' ? annotation_array : annotation_hash[:values],
          text: text_array,
          cells: cells,
          name: annotation[:name],
          marker: {
              cmax: max,
              cmin: min,
              color: color_array,
              size: study.default_cluster_point_size,
              line: { color: 'rgb(40,40,40)', width: study.show_cluster_point_borders? ? 0.5 : 0},
              colorscale: params[:colorscale].blank? ? 'Reds' : params[:colorscale],
              showscale: true,
              colorbar: {
                  title: annotation[:name] ,
                  titleside: 'right'
              }
          }
      }
      if cluster.is_3d?
        coordinates[:all][:z] = z_array
      end
    else
      # assemble containers for each trace
      annotation[:values].each do |value|
        coordinates[value] = {x: [], y: [], text: [], cells: [], annotations: [], name: value,
                              marker: {size: study.default_cluster_point_size, line: { color: 'rgb(40,40,40)', width: study.show_cluster_point_borders? ? 0.5 : 0}}}
        if cluster.is_3d?
          coordinates[value][:z] = []
        end
      end

      if annotation[:scope] == 'cluster' || annotation[:scope] == 'user'
        annotation_array.each_with_index do |annotation_value, index|
          coordinates[annotation_value][:text] << "<b>#{cells[index]}</b><br>#{annotation_value}"
          coordinates[annotation_value][:annotations] << annotation_value
          coordinates[annotation_value][:cells] << cells[index]
          coordinates[annotation_value][:x] << x_array[index]
          coordinates[annotation_value][:y] << y_array[index]
          if cluster.is_3d?
            coordinates[annotation_value][:z] << z_array[index]
          end
        end
        coordinates.each do |key, data|
          data[:name] << " (#{data[:x].size} points)"
        end
      else
        cells.each_with_index do |cell, index|
          if annotation_hash.has_key?(cell)
            annotation_value = annotation_hash[cell]
            coordinates[annotation_value][:text] << "<b>#{cell}</b><br>#{annotation_value}"
            coordinates[annotation_value][:annotations] << annotation_value
            coordinates[annotation_value][:x] << x_array[index]
            coordinates[annotation_value][:y] << y_array[index]
            coordinates[annotation_value][:cells] << cell
            if cluster.is_3d?
              coordinates[annotation_value][:z] << z_array[index]
            end
          end
        end
        coordinates.each do |key, data|
          data[:name] << " (#{data[:x].size} points)"
        end

      end

    end
    # gotcha to remove entries in case a particular annotation value comes up blank since this is study-wide
    coordinates.delete_if {|key, data| data[:x].empty?}
    coordinates
  end
end
