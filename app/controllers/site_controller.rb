class SiteController < ApplicationController

  respond_to :html, :js

  before_action :set_study, except: [:index, :search]
  before_action :load_precomputed_options, except: [:index, :search]
  before_action :set_cluster_group, except: [:index, :search, :view_all_gene_expression_heatmap, :precomputed_results]
  before_action :set_selected_annotation, except: [:index, :search, :precomputed_results]
  COLORSCALE_THEMES = ['Blackbody', 'Bluered', 'Blues', 'Earth', 'Electric', 'Greens', 'Hot', 'Jet', 'Picnic', 'Portland', 'Rainbow', 'RdBu', 'Reds', 'Viridis', 'YlGnBu', 'YlOrRd']

  # view study overviews and downloads
  def index
    @study_count = Study.count
    @cell_count = Study.all.map(&:cell_count).inject(&:+)
    # set study order
    case params[:order]
      when 'recent'
        @order = :created_at.desc
      when 'popular'
        @order = :view_count.desc
      else
        @order = [:view_order.asc, :name.asc]
    end

    # load viewable studies in requested order
    if user_signed_in?
      @viewable = Study.viewable(current_user).order_by(@order)
    else
      @viewable = Study.where(public: true).order_by(@order)
    end

    # if search params are present, filter accordingly
    if !params[:search_terms].blank?
      @studies = @viewable.where({:$text => {:$search => params[:search_terms]}}).paginate(page: params[:page], per_page: Study.per_page)
    else
      @studies = @viewable.paginate(page: params[:page], per_page: Study.per_page)
    end
  end

  # search for matching studies
  def search
    # use built-in MongoDB text index (supports quoting terms & case sensitivity)
    @studies = Study.where({:$text => {:$search => params[:search_terms]}})
    render 'index'
  end

  # load single study and view top-level clusters
  def study
    @study.update(view_count: @study.view_count + 1)
    # parse all coordinates out into hash using generic method
    if @study.initialized?
      @options = load_cluster_group_options
      @cluster_annotations = load_cluster_group_annotations
    end
  end

  # render a single cluster and its constituent sub-clusters
  def render_cluster
    @coordinates = load_cluster_group_data_array_points(@selected_annotation)
    @plot_type = @cluster.cluster_type == '3d' ? 'scatter3d' : 'scattergl'
    @options = load_cluster_group_options
    @cluster_annotations = load_cluster_group_annotations
    @range = set_range(@coordinates.values)
    @axes = load_axis_labels
  end

  # search for one or more genes to view expression information
  def search_genes
    if params[:search][:upload].blank?
      terms = parse_search_terms(:genes)
      @genes = load_expression_scores(terms)
    else
      geneset_file = params[:search][:upload]
      terms = geneset_file.read.split(/[\s\r\n?,]/).map {|gene| gene.strip.downcase}
      @genes = load_expression_scores(terms)
    end
    # grab saved params for loaded cluster and boxpoints mode
    cluster = params[:search][:cluster]
    annotation = params[:search][:annotation]
    boxpoints = params[:search][:boxpoints]
    if @genes.empty?
      redirect_to request.referrer, alert: "No matches found for: #{terms.join(', ')}."
    elsif @genes.size > 1
      redirect_to view_gene_expression_heatmap_path(search: {genes: terms.join(' ')}, cluster: cluster, annotation: annotation)
    else
      gene = @genes.first
      redirect_to view_gene_expression_path(study_name: params[:study_name], gene: gene.gene, cluster: cluster, boxpoints: boxpoints, annotation: annotation)
    end
  end

  # render box and scatter plots for parent clusters or a particular sub cluster
  def view_gene_expression
    @gene = @study.expression_scores.by_gene(params[:gene])
    @options = load_cluster_group_options
    @cluster_annotations = load_cluster_group_annotations
    @top_plot_partial = @selected_annotation[:type] == 'group' ? 'expression_plots_view' : 'expression_annotation_plots_view'
  end

  # re-renders plots when changing cluster selection
  def render_gene_expression_plots
    @gene = @study.expression_scores.by_gene(params[:gene])
    @y_axis_title = @study.expression_matrix_file.y_axis_label
    # depending on annotation type selection, set up necessary partial names to use in rendering
    if @selected_annotation[:type] == 'group'
      @values = load_expression_boxplot_data_array_scores(@selected_annotation)
      @top_plot_partial = 'expression_plots_view'
      @top_plot_plotly = 'expression_plots_plotly'
      @top_plot_layout = 'expression_box_layout'
    else
      @values = load_annotation_based_data_array_scatter(@selected_annotation)
      @top_plot_partial = 'expression_annotation_plots_view'
      @top_plot_plotly = 'expression_annotation_plots_plotly'
      @top_plot_layout = 'expression_annotation_scatter_layout'
      @annotation_scatter_range = set_range(@values.values)
    end
    @expression = load_expression_data_array_points(@selected_annotation)
    @options = load_cluster_group_options
    @range = set_range([@expression[:all]])
    @coordinates = load_cluster_group_data_array_points(@selected_annotation)
    @static_range = set_range(@coordinates.values)
    if @selected_annotation[:type] == 'group'
      @annotations = load_static_annotations(@static_range, @selected_annotation)
    end
    @cluster_annotations = load_cluster_group_annotations
  end

  # view set of genes (scores averaged) as box and scatter plots
  def view_gene_set_expression
    precomputed = @study.precomputed_scores.by_name(params[:gene_set])
    @genes = []
    precomputed.gene_list.map {|gene| @genes << @study.expression_scores.by_gene(gene)}
    @y_axis_title = 'Mean ' + @study.expression_matrix_file.y_axis_label
    # depending on annotation type selection, set up necessary partial names to use in rendering
		@options = load_cluster_group_options
		@cluster_annotations = load_cluster_group_annotations
		@top_plot_partial = @selected_annotation[:type] == 'group' ? 'expression_plots_view' : 'expression_annotation_plots_view'

    if @genes.size > 5
      @main_genes, @other_genes = divide_genes_for_header
    end
    render 'view_gene_expression'
  end

  # re-renders plots when changing cluster selection
  def render_gene_set_expression_plots
    precomputed = @study.precomputed_scores.by_name(params[:gene_set])
    @genes = []
    precomputed.gene_list.map {|gene| @genes << @study.expression_scores.by_gene(gene)}
    @y_axis_title = 'Mean ' + @study.expression_matrix_file.y_axis_label
    # depending on annotation type selection, set up necessary partial names to use in rendering
    if @selected_annotation[:type] == 'group'
      @values = load_gene_set_expression_boxplot_scores(@selected_annotation)
      @top_plot_partial = 'expression_plots_view'
      @top_plot_plotly = 'expression_plots_plotly'
      @top_plot_layout = 'expression_box_layout'
    else
      @values = load_gene_set_annotation_based_scatter(@selected_annotation)
      @top_plot_partial = 'expression_annotation_plots_view'
      @top_plot_plotly = 'expression_annotation_plots_plotly'
      @top_plot_layout = 'expression_annotation_scatter_layout'
      @annotation_scatter_range = set_range(@values.values)
    end
    # load expression scatter using main gene expression values
    @expression = load_gene_set_expression_data_arrays(@selected_annotation)
    color_minmax =  @expression[:all][:marker][:color].minmax
    @expression[:all][:marker][:cmin], @expression[:all][:marker][:cmax] = color_minmax
    @expression[:all][:marker][:colorscale] = 'Reds'
    # load static cluster reference plot
    @coordinates = load_cluster_group_data_array_points(@selected_annotation)
    # set up options, annotations and ranges
    @options = load_cluster_group_options
    @range = set_range([@expression[:all]])
    @static_range = set_range(@coordinates.values)
    @cluster_annotations = load_cluster_group_annotations
    if @selected_annotation[:type] == 'group'
      @annotations = load_static_annotations(@static_range, @selected_annotation)
    end

    if @genes.size > 5
      @main_genes, @other_genes = divide_genes_for_header
    end
    render 'render_gene_expression_plots'
  end

  # view genes in Morpheus as heatmap
  def view_gene_expression_heatmap
    # parse and divide up genes
    terms = parse_search_terms(:genes)
    @genes, @not_found = search_expression_scores(terms)

    # load dropdown options
    @options = load_cluster_group_options
    @cluster_annotations = load_cluster_group_annotations
    if @genes.size > 5
      @main_genes, @other_genes = divide_genes_for_header
    end

    # select cluster file to load annotations from
    @cluster_file = @study.cluster_ordinations_file(params[:cluster])
    if @study.public?
      @clusters_url = @cluster_file.download_path
    else
      @clusters_url = TempFileDownload.create!({study_file_id: @cluster_file._id}).download_url
    end
  end

  # load data in gct form to render in Morpheus, preserving query order
  def expression_query
    terms = parse_search_terms(:genes)
    @genes = load_expression_scores(terms)
    @headers = ["Name", "Description"]
    @cells = @cluster.concatenate_data_arrays('text', 'cells')
    @cols = @cells.size
    @cells.each do |cell|
      @headers << cell
    end

    @rows = []
    @genes.each do |gene|
      row = [gene.gene, ""]
      # calculate mean to perform row centering if requested
      mean = 0.0
      if params[:row_centered] == '1'
        mean = gene.mean(@cells)
      end
      @cells.each do |cell|
        row << gene.scores[cell].to_f - mean
      end

      @rows << row.join("\t")
    end
    @data = ['#1.2', [@rows.size, @cols].join("\t"), @headers.join("\t"), @rows.join("\n")].join("\n")

    send_data @data, type: 'text/plain'
  end

  # load precomputed data in gct form to render in Morpheus
  def precomputed_results
    @precomputed_score = @study.precomputed_scores.by_name(params[:precomputed])

    @headers = ["Name", "Description"]
    @precomputed_score.clusters.each do |cluster|
      @headers << cluster
    end
    @rows = []
    @precomputed_score.gene_scores.each do |score_row|
      score_row.each do |gene, scores|
        row = [gene, ""]
        mean = 0.0
        if params[:row_centered] == '1'
          mean = scores.values.inject(0) {|sum, x| sum += x} / scores.values.size
        end
        @precomputed_score.clusters.each do |cluster|
          row << scores[cluster].to_f - mean
        end
        @rows << row.join("\t")
      end
    end
    @data = ['#1.2', [@rows.size, @precomputed_score.clusters.size].join("\t"), @headers.join("\t"), @rows.join("\n")].join("\n")

    send_data @data, type: 'text/plain', filename: 'query.gct'
  end

  # view all genes as heatmap in morpheus, will pull from pre-computed gct file
  def view_all_gene_expression_heatmap
  end

  # redirect to show precomputed marker gene results
  def search_precomputed_results
    redirect_to view_precomputed_gene_expression_heatmap_path(study_name: params[:study_name], precomputed: params[:expression])
  end

  # view all genes as heatmap in morpheus, will pull from pre-computed gct file
  def view_precomputed_gene_expression_heatmap
    @precomputed_score = @study.precomputed_scores.by_name(params[:precomputed])
    @options = load_cluster_group_options
    @cluster_annotations = load_cluster_group_annotations
  end

  private

  # SETTERS
  def set_study
    @study = Study.where(url_safe_name: params[:study_name]).first
  end

  def set_cluster_group
    # determine which URL param to use for selection
    selector = params[:cluster].nil? ? params[:gene_set_cluster] : params[:cluster]
    if selector.nil?
      @cluster = @study.cluster_groups.first
    else
      @cluster = @study.cluster_groups.select {|c| c.name == selector}.first
    end
  end

  def set_selected_annotation
    # determine which URL param to use for selection
    selector = params[:annotation].nil? ? params[:gene_set_annotation] : params[:annotation]
    if selector.nil?
      @selected_annotation = @cluster.cell_annotations.first
    else
      @selected_annotation = @cluster.cell_annotations.select {|ca| ca[:name] == selector}.first
    end
	end

	# SUB METHODS

  # generic method to populate data structure to render a cluster scatter plot
  # uses cluster_group model and loads annotation for both group & numeric plots
  # data values are pulled from associated data_array entries for each axis and annotation/text value
  def load_cluster_group_data_array_points(annotation)
    x_array = @cluster.concatenate_data_arrays('x', 'coordinates')
    y_array = @cluster.concatenate_data_arrays('y', 'coordinates')
    z_array = @cluster.concatenate_data_arrays('z', 'coordinates')
    cells = @cluster.concatenate_data_arrays('text', 'cells')
    annotation_array = @cluster.concatenate_data_arrays(annotation[:name], 'annotations')
    coordinates = {}
    if annotation[:type] == 'numeric'
      text_array = []
      cells.each_with_index do |cell, index|
        text_array << "#{cell}: (#{annotation_array[index]})"
      end
      coordinates[:all] = {
          x: x_array,
          y: y_array,
          z: z_array,
          text: text_array,
          name: annotation[:name],
          marker: {
              cmax: annotation_array.max,
              cmin: annotation_array.min,
              color: annotation_array,
              size: annotation_array.map {|a| 6},
              line: { color: 'rgb(40,40,40)', width: 0.5},
              showscale: true,
              colorbar: {
                  title: annotation[:name] ,
                  titleside: 'right'
              }
          }
      }
    else
      annotation[:values].each do |value|
        coordinates[value] = {x: [], y: [], z: [], text: [], name: "#{annotation[:name]}: #{value}", marker_size: []}
      end
      annotation_array.each_with_index do |annotation_value, index|
        coordinates[annotation_value][:text] << "<b>#{cells[index]}</b><br>#{annotation[:name]}: #{annotation_value}".html_safe
        coordinates[annotation_value][:x] << x_array[index]
        coordinates[annotation_value][:y] << y_array[index]
        if @cluster.cluster_type == '3d'
          coordinates[annotation_value][:z] << z_array[index]
        end
        coordinates[annotation_value][:marker_size] << 6
      end
      coordinates.each do |key, data|
        data[:name] << " (#{data[:x].size} points)"
      end
    end
    coordinates
  end

  # method to load a 2-d scatter of selected numeric annotation vs. gene expression
  def load_annotation_based_data_array_scatter(annotation)
    cells = @cluster.concatenate_data_arrays('text', 'cells')
    annotation_array = @cluster.concatenate_data_arrays(annotation[:name], 'annotations')
    values = {}
    values[:all] = {x: [], y: [], text: [], marker_size: []}
    annotation_array.each_with_index do |annot, index|
      annotation_value = annot
      cell_name = cells[index]
      expression_value = @gene.scores[cell_name].to_f.round(4)
      values[:all][:text] << "<b>#{cell_name}</b><br>#{annotation[:name]}: #{annotation_value}<br>#{@y_axis_title}: #{expression_value}"
      values[:all][:x] << annotation_value
      values[:all][:y] << expression_value
      values[:all][:marker_size] << 6
    end
    values
  end

  # method to load a 2-d scatter of selected numeric annotation vs. gene set expression (mean)
  def load_gene_set_annotation_based_scatter(annotation)
    values = {}
    values[:all] = {x: [], y: [], text: [], marker_size: []}
		cells = @cluster.concatenate_data_arrays('text', 'cells')
		annotation_array = @cluster.concatenate_data_arrays(annotation[:name], 'annotations')
    cells.each_with_index do |cell|
      annotation_value = annotation_array[index]
      expression_value = calculate_mean(@genes, cell)
      values[:all][:text] << "<b>#{cell}</b><br>#{annotation[:name]}: #{annotation_value}<br>#{@y_axis_title}: #{expression_value}"
      values[:all][:x] << annotation_value
      values[:all][:y] << expression_value
      values[:all][:marker_size] << 6
    end
    values
  end

  # loads annotations array if being used for reference plot
  def load_static_annotations(range, annotation)
    # initialize objects and divide cluster points by annotation values
    annotations = []
    cell_groups = divide_data_array_by_annotation_value(annotation)
    # create plotly annotation objects
    cell_groups.each do |annot_val, values|
      # calculate median position for cluster labels
      full_range = range.first.abs + range.last.abs
      x_positions = values[:x].sort
      y_positions = values[:y].sort
      x_len = x_positions.size
      y_len = y_positions.size
      x_mid = x_positions.inject(0.0) { |sum, el| sum + el } / x_len
      y_mid = y_positions.inject(0.0) { |sum, el| sum + el } / y_len
      x_pos = (x_mid + range.first.abs) / full_range
      y_pos = (y_mid + range.first.abs) / full_range
      if @cluster.is_3d?
        z_positions = values[:z].sort
        z_len = z_positions.size
        z_mid = z_positions.inject(0.0) { |sum, el| sum + el } / z_len
        @z_pos = (z_mid + range.first.abs) / full_range
      end
      annot = {
          xref: 'paper',
          yref: 'paper',
          x: x_pos,
          y: y_pos,
          text: "#{annotation[:name]}: #{annot_val}",
          showarrow: false,
          borderpad: 4,
          bgcolor: '#efefef',
          bordercolor: '#ccc',
          borderwidth: 1,
          opacity: 0.6,
          font: annotation_font
      }
      if @cluster.is_3d?
        annot[:z] = @z_pos
      end
      annotations << annot
    end
    annotations
  end

  # load box plot scores from gene expression values using data array of cell names for given cluster
  def load_expression_boxplot_data_array_scores(annotation)
    values = initialize_plotly_objects_by_annotation(annotation)

    # grab all cells present in the cluster, and use as keys to load expression scores
    # if a cell is not present for the gene, score gets set as 0.0
    # will check if there are more than ClusterGroup::SUBSAMPLE_THRESHOLD cells present in the cluster, and subsample accordingly
    all_cells = @cluster.concatenate_data_arrays('text', 'cells')
    all_annotations = @cluster.concatenate_data_arrays(annotation[:name], 'annotations')
    cells = all_cells.count > ClusterGroup::SUBSAMPLE_THRESHOLD ? all_cells.shuffle(random: Random.new(1)).take(ClusterGroup::SUBSAMPLE_THRESHOLD) : all_cells
    annotations = all_annotations.count > ClusterGroup::SUBSAMPLE_THRESHOLD ? all_annotations.shuffle(random: Random.new(1)).take(ClusterGroup::SUBSAMPLE_THRESHOLD) : all_annotations
    cells.each_with_index do |cell, index|
      values[annotations[index]][:y] << @gene.scores[cell].to_f.round(4)
    end
    values
  end

  # load cluster_group data_array values, but use expression scores to set numerical color array
  def load_expression_data_array_points(annotation)
    x_array = @cluster.concatenate_data_arrays('x', 'coordinates')
    y_array = @cluster.concatenate_data_arrays('y', 'coordinates')
    z_array = @cluster.concatenate_data_arrays('z', 'coordinates')
    cells = @cluster.concatenate_data_arrays('text', 'cells')
    annotation_array = @cluster.concatenate_data_arrays(annotation[:name], 'annotations')
    expression = {}
    expression[:all] = {
        x: x_array,
        y: y_array,
        z: z_array,
        text: [],
        marker: {cmax: 0, cmin: 0, color: [], size: [], showscale: true, colorbar: {title: @y_axis_title , titleside: 'right'}}
    }
    cells.each_with_index do |cell, index|
      expression_score = @gene.scores[cell].to_f.round(4)
      text_value = "#{cell} (#{annotation[:name]}: #{annotation_array[index]})<br />#{@y_axis_title}: #{expression_score}"
      expression[:all][:text] << text_value
      expression[:all][:marker][:color] << expression_score
      expression[:all][:marker][:size] << 6
    end
    color_minmax =  expression[:all][:marker][:color].minmax
    expression[:all][:marker][:cmin], expression[:all][:marker][:cmax] = color_minmax
    expression[:all][:marker][:colorscale] = 'Reds'
    expression
  end

  # load boxplot expression scores with average of scores across each gene for all cells
  def load_gene_set_expression_boxplot_scores(annotation)
		values = initialize_plotly_objects_by_annotation(annotation)

		# grab all cells present in the cluster, and use as keys to load expression scores
		# if a cell is not present for the gene, score gets set as 0.0
		# will check if there are more than ClusterGroup::SUBSAMPLE_THRESHOLD cells present in the cluster, and subsample accordingly
		all_cells = @cluster.concatenate_data_arrays('text', 'cells')
		all_annotations = @cluster.concatenate_data_arrays(annotation[:name], 'annotations')
		cells = all_cells.count > ClusterGroup::SUBSAMPLE_THRESHOLD ? all_cells.shuffle(random: Random.new(1)).take(ClusterGroup::SUBSAMPLE_THRESHOLD) : all_cells
		annotations = all_annotations.count > ClusterGroup::SUBSAMPLE_THRESHOLD ? all_annotations.shuffle(random: Random.new(1)).take(ClusterGroup::SUBSAMPLE_THRESHOLD) : all_annotations
		cells.each_with_index do |cell, index|
      values[annotations[index]][:y] << calculate_mean(@genes, cell)
    end
    values
  end

  # load scatter expression scores with average of scores across each gene for all cells
	# uses data_array as source for each axis
	def load_gene_set_expression_data_arrays(annotation)
		x_array = @cluster.concatenate_data_arrays('x', 'coordinates')
		y_array = @cluster.concatenate_data_arrays('y', 'coordinates')
		z_array = @cluster.concatenate_data_arrays('z', 'coordinates')
		cells = @cluster.concatenate_data_arrays('text', 'cells')
		annotation_array = @cluster.concatenate_data_arrays(annotation[:name], 'annotations')
		expression = {}
		expression[:all] = {
				x: x_array,
				y: y_array,
				z: z_array,
				text: [],
				marker: {cmax: 0, cmin: 0, color: [], size: [], showscale: true, colorbar: {title: @y_axis_title , titleside: 'right'}}
		}
		cells.each_with_index do |cell, index|
			expression_score = calculate_mean(@genes, cell)
			text_value = "#{cell} (#{annotation[:name]}: #{annotation_array[index]})<br />#{@y_axis_title}: #{expression_score}"
			expression[:all][:text] << text_value
			expression[:all][:marker][:color] << expression_score
			expression[:all][:marker][:line] = { color: 'rgb(40,40,40)', width: 0.5}
			expression[:all][:marker][:size] << 6
		end
		color_minmax =  expression[:all][:marker][:color].minmax
		expression[:all][:marker][:cmin], expression[:all][:marker][:cmax] = color_minmax
		expression[:all][:marker][:colorscale] = 'Reds'
		expression
	end

  # generic method to divide a collection of cells/points by an annotation value
  def divide_data_array_by_annotation_value(annotation)
    x_array = @cluster.concatenate_data_arrays('x', 'coordinates')
    y_array = @cluster.concatenate_data_arrays('y', 'coordinates')
    z_array = @cluster.concatenate_data_arrays('z', 'coordinates')
    annotation_array = @cluster.concatenate_data_arrays(annotation[:name], 'annotations')
    annotation_groups = {}
    annotation[:values].each do |annot|
      annotation_groups[annot] = {x: [], y: [], z: []}
    end
    # divide up points by selected annotation value
    annotation_array.each_with_index do |annot, index|
      annotation_groups[annot][:x] << x_array[index]
      annotation_groups[annot][:y] << y_array[index]
      annotation_groups[annot][:z] << z_array[index]
    end
    annotation_groups
  end

  # method to initialize containers for plotly by annotation values
  def initialize_plotly_objects_by_annotation(annotation)
    values = {}
    annotation[:values].each do |value|
      values["#{value}"] = {y: [], name: "#{annotation[:name]}: #{value}" }
    end
    values
  end

  # find mean of expression scores for a given cell
  def calculate_mean(genes, cell)
    sum = 0.0
    genes.each do |gene|
      sum += gene.scores[cell].to_f
    end
    sum / genes.size
  end

  # generic search term parser
  def parse_search_terms(key)
    terms = params[:search][key]
    if terms.is_a?(Array)
      terms.first.split(/[\s\n,]/).map {|gene| gene.strip}
    else
      terms.split(/[\s\n,]/).map {|gene| gene.strip}
    end
  end

  # generic expression score getter, preserves order and discards empty matches
  def load_expression_scores(terms)
    genes = []
    terms.each do |term|
      g = @study.expression_scores.by_gene(term)
      genes << g unless g.nil?
    end
    genes
  end

  # search genes and save terms not found
  def search_expression_scores(terms)
    genes = []
    not_found = []
    terms.each do |term|
      gene = @study.expression_scores.by_gene(term)
      unless gene.nil?
        genes << gene
      else
        not_found << term
      end
    end
    [genes, not_found]
  end

  # helper method to load all possible cluster groups for a study
  def load_cluster_group_options
    @study.cluster_groups.map(&:name)
  end

  # helper method to load all available cluster_group-specific annotations
  def load_cluster_group_annotations(type=nil)
    if type.nil?
      @cluster.cell_annotations.map {|annot| ["#{annot[:name]} (#{annot[:type]})", annot[:name]]}
    else
      @cluster.cell_annotations.select {|ca| ca[:type] == type}.map {|annot| ["#{annot[:name]} (#{annot[:type]})", annot[:name]]}
    end
  end

  # defaults for annotation fonts
  def annotation_font
    {
        family: 'Helvetica Neue',
        size: 10,
        color: '#333'
    }
  end

  # set the range for a plotly scatter
  def set_range(inputs)
    vals = inputs.map {|v| [v[:x].minmax, v[:y].minmax]}.flatten.minmax
    # add 2% padding to range
    scope = (vals.first - vals.last) * 0.02
    [vals.first + scope, vals.last - scope]
  end

  # parse gene list into 2 other arrays for formatting the header responsively
  def divide_genes_for_header
    main = @genes[0..4]
    more = @genes[5..@genes.size - 1]
    [main, more]
  end

  # load all precomputed options for a study
  def load_precomputed_options
     @precomputed = @study.precomputed_scores.map(&:name)
  end

  # retrieve axis labels from cluster coordinates file (if provided)
  def load_axis_labels
    coordinates_file = @cluster.study_file
    {
        x: coordinates_file.x_axis_label,
        y: coordinates_file.y_axis_label
    }
  end
end
