class RequestUtils

  # load same sanitizer as ActionView for stripping html/js from inputs
  # using FullSanitizer as it is the most strict
  SANITIZER ||= Rails::Html::FullSanitizer.new

  # Convert cluster group data array points into JSON plot data for Plotly
  #
  # Consider extracting this method and other SCP-specific methods to a separate class
  # ClusterService.rb, perhaps?
  def self.transform_coordinates(coordinates, plot_type, study, cluster_group, selected_annotation)
    plot_data = []

    coordinates.sort_by {|k,v| k}.each_with_index do |(cluster, data), index|
      cluster_props = {
        x: data[:x],
        y: data[:y],
        cells: data[:cells],
        text: data[:text],
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

      if selected_annotation[:type] == 'group'
        # Set color index that will be interpreted by SCP front end
        cluster_props[:marker][:scpColorIndex] = index
      end

      plot_data.push(cluster_props)
    end

    plot_data
  end


  def self.get_selected_annotation(params, study, cluster)
    selector = params[:annotation].nil? ? params[:gene_set_annotation] : params[:annotation]
    annot_name, annot_type, annot_scope = selector.nil? ? study.default_annotation.split('--') : selector.split('--')

    # construct object based on name, type & scope
    case annot_scope
    when 'cluster'
      annotation_source = cluster.cell_annotations.find {|ca| ca[:name] == annot_name && ca[:type] == annot_type}
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
  def self.populate_annotation_by_class(source:, scope:, type:)
    if source.is_a?(CellMetadatum)
      annotation = {name: source.name, type: source.annotation_type,
                    scope: 'study', values: source.values.to_a,
                    identifier: "#{source.name}--#{type}--#{scope}"}
    elsif source.is_a?(UserAnnotation)
      annotation = {name: source.name, type: type, scope: scope, values: source.values.to_a,
                    identifier: "#{source.id}--#{type}--#{scope}", id: source.id}
    elsif source.is_a?(Hash)
      annotation = {name: source[:name], type: type, scope: scope, values: source[:values].to_a,
                    identifier: "#{source[:name]}--#{type}--#{scope}"}
    end
    annotation
  end

  def self.get_cluster_group(params, study)
    # determine which URL param to use for selection
    selector = params[:cluster].nil? ? params[:gene_set_cluster] : params[:cluster]
    puts 'selector'
    puts selector
    if selector.nil? || selector.empty?
      study.default_cluster
    else
      study.cluster_groups.by_name(selector)
    end
  end

  # sanitizes a page param into an integer.  Will default to 1 if the value
  # is nil or otherwise can't be read
  def self.sanitize_page_param(page_param)
    page_num = 1
    parsed_num = page_param.to_i
    if (parsed_num > 0)
      page_num = parsed_num
    end
    page_num
  end

  # safely determine min/max bounds of an array, accounting for NaN value
  def self.get_minmax(values_array)
    begin
      values_array.minmax
    rescue TypeError, ArgumentError
      values_array.dup.reject!(&:nan?).minmax
    end
  end

  # safely strip unsafe characters and encode search parameters for query/rendering
  # strips out unsafe characters that break rendering notices/modals
  def self.sanitize_search_terms(terms)
    inputs = terms.is_a?(Array) ? terms.join(',') : terms.to_s
    SANITIZER.sanitize(inputs).encode('ASCII-8BIT', invalid: :replace, undef: :replace)
  end
end
