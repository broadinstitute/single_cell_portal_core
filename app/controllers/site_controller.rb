class SiteController < ApplicationController

  respond_to :html, :js

  before_action :set_study, except: [:index, :search]
  before_action :load_precomputed_options, except: [:index, :search]
  before_action :set_clusters, except: [:index, :search, :view_all_gene_expression_heatmap, :precomputed_results]

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
      @coordinates = load_cluster_points
      @options = load_sub_cluster_options
      @range = set_range(@coordinates.values)
    end
  end

  # render a single cluster and its constituent sub-clusters
  def render_cluster
    @coordinates = load_cluster_points
    @options = load_sub_cluster_options
    @range = set_range(@coordinates.values)
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
    boxpoints = params[:search][:boxpoints]
    if @genes.empty?
      redirect_to request.referrer, alert: "No matches found for: #{terms.join(', ')}"
    elsif @genes.size > 1
      if !cluster.blank?
        redirect_to view_gene_expression_heatmap_path(search: {genes: terms.join(' ')}, cluster: cluster)
      else
        redirect_to view_gene_expression_heatmap_path(search: {genes: terms.join(' ')})
      end
    else
      gene = @genes.first
      # determine whether to show all sub-clusters grouped by parent, or an individual sub-cluster
      if !cluster.blank?
        redirect_to view_gene_expression_path(study_name: params[:study_name], gene: gene.gene, cluster: cluster, boxpoints: boxpoints)
      else
        redirect_to view_gene_expression_path(study_name: params[:study_name], gene: gene.gene, boxpoints: boxpoints)
      end
    end
  end

  # render box and scatter plots for parent clusters or a particular sub cluster
  def view_gene_expression
    @gene = @study.expression_scores.by_gene(params[:gene])
    @y_axis_title = 'log(TPM) Expression Values'
    @values = load_expression_boxplot_scores
    @coordinates = load_cluster_points
    @expression = load_expression_scatter_points
    color_minmax =  @expression[:all][:marker][:color].minmax
    @expression[:all][:marker][:cmin], @expression[:all][:marker][:cmax] = color_minmax
    @expression[:all][:marker][:colorscale] = 'Reds'
    @options = load_sub_cluster_options
    @range = set_range([@expression[:all]])
    @static_range = set_range(@coordinates.values)
    @annotations = load_cluster_annotations(@static_range)
  end

  # re-renders plots when changing cluster selection
  def render_gene_expression_plots
    @gene = @study.expression_scores.by_gene(params[:gene])
    @y_axis_title = 'log(TPM) Expression Values'
    @values = load_expression_boxplot_scores
    @coordinates = load_cluster_points
    @expression = load_expression_scatter_points
    color_minmax =  @expression[:all][:marker][:color].minmax
    @expression[:all][:marker][:cmin], @expression[:all][:marker][:cmax] = color_minmax
    @expression[:all][:marker][:colorscale] = 'Reds'
    @options = load_sub_cluster_options
    @range = set_range([@expression[:all]])
    @static_range = set_range(@coordinates.values)
    @annotations = load_cluster_annotations(@static_range)
  end

  # view set of genes (scores averaged) as box and scatter plots
  def view_gene_set_expression
    precomputed = @study.precomputed_scores.by_name(params[:gene_set])
    @genes = []
    precomputed.gene_list.map {|gene| @genes << @study.expression_scores.by_gene(gene)}
    @y_axis_title = 'Mean-centered average of log(TPM) Expression Values'
    @values = load_gene_set_expression_boxplot_scores
    @coordinates = load_cluster_points

    @expression = load_gene_set_expression_scatter_points
    color_minmax =  @expression[:all][:marker][:color].minmax
    @expression[:all][:marker][:cmin], @expression[:all][:marker][:cmax] = color_minmax
    @expression[:all][:marker][:colorscale] = 'Reds'
    @options = load_sub_cluster_options
    @range = set_range([@expression[:all]])
    @static_range = set_range(@coordinates.values)
    @annotations = load_cluster_annotations(@static_range)
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
    @y_axis_title = 'Mean-centered average of log(TPM) Expression Values'
    @values = load_gene_set_expression_boxplot_scores
    @coordinates = load_cluster_points
    @annotations = load_cluster_annotations
    @expression = load_gene_set_expression_scatter_points
    color_minmax =  @expression[:all][:marker][:color].minmax
    @expression[:all][:marker][:cmin], @expression[:all][:marker][:cmax] = color_minmax
    @expression[:all][:marker][:colorscale] = 'Reds'
    @options = load_sub_cluster_options
    @range = set_range([@expression[:all]])
    @static_range = set_range(@coordinates.values)
    if @genes.size > 5
      @main_genes, @other_genes = divide_genes_for_header
    end
    render 'render_gene_expression_plots'
  end

  # view genes in Morpheus as heatmap
  def view_gene_expression_heatmap
    terms = parse_search_terms(:genes)
    @genes, @not_found = search_expression_scores(terms)
    @options = load_sub_cluster_options
    if @genes.size > 5
      @main_genes, @other_genes = divide_genes_for_header
    end
    if @study.public?
      @clusters_url = @study.cluster_assignment_file.download_path
    else
      @clusters_url = TempFileDownload.create!({study_file_id: @study.cluster_assignment_file._id}).download_url
    end
  end

  # load data in gct form to render in Morpheus, preserving query order
  def expression_query
    terms = parse_search_terms(:genes)
    @genes = load_expression_scores(terms)
    @cols = @clusters.map {|c| c.single_cells.size}.inject(0) {|sum, x| sum += x}
    @headers = ["Name", "Description"]
    @clusters.each do |cluster|
      cluster.single_cells.each do |cell|
        @headers << cell.name
      end
    end
    @rows = []
    @genes.each do |gene|
      row = [gene.gene, ""]
      @clusters.each do |cluster|
        cells = cluster.single_cells
        # calculate mean to perform row centering if requested
        mean = 0.0
        if params[:row_centered] == '1'
          mean = gene.mean(cells.map(&:name))
        end
        cells.each do |cell|
          row << gene.scores[cell.name].to_f - mean
        end
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
  end

  private

  # generic method to populate data structure to render a cluster scatterplot
  def load_cluster_points
    coordinates = {}
    @clusters.each do |cluster|
      coordinates[cluster.name] = {x: [], y: [], text: [], marker_size: [], name: "#{cluster.name}  (#{cluster.cluster_points.size} points)"}
      points = cluster.cluster_points
      points.each do |point|
        coordinates[cluster.name][:text] << "#{point.cell_name} <br>[#{cluster.name}]"
        coordinates[cluster.name][:x] << point.x
        coordinates[cluster.name][:y] << point.y
        coordinates[cluster.name][:marker_size] << 6
      end
    end
    coordinates
  end

  # loads annotations array if being used for reference plot
  def load_cluster_annotations(range)
    annotations = []
    @clusters.each do |cluster|
      # calculate median position for cluster labels
      full_range = range.first.abs + range.last.abs
      x_positions = cluster.cluster_points.map(&:x).sort
      y_positions = cluster.cluster_points.map(&:y).sort
      x_len = x_positions.size
      y_len = y_positions.size
      x_mid = x_positions.inject(0.0) { |sum, el| sum + el } / x_len
      y_mid = y_positions.inject(0.0) { |sum, el| sum + el } / y_len
      x_pos = (x_mid + range.first.abs) / full_range
      y_pos = (y_mid + range.first.abs) / full_range
      annotations << {
          xref: 'paper',
          yref: 'paper',
          x: x_pos,
          y: y_pos,
          text: cluster.name,
          showarrow: false,
          borderpad: 4,
          bgcolor: '#efefef',
          bordercolor: '#ccc',
          borderwidth: 1,
          opacity: 0.6,
          font: annotation_font
      }
    end
    annotations
  end

  # generic method to populate data structure to render a box plot
  def load_expression_boxplot_scores
    values = {}
    @clusters.each do |cluster|
      values[cluster.name] = {y: [], name: cluster.name }
      # grab all cells present in the cluster, and use as keys to load expression scores
      # if a cell is not present for the gene, score gets set as 0.0
      cluster.single_cells.map(&:name).each do |cell|
        values[cluster.name][:y] << @gene.scores[cell].to_f
      end
    end
    values
  end

  # load cluster plot, but use expression scores to set numerical color array
  def load_expression_scatter_points
    expression = {}

    expression[:all] = {x: [], y: [], text: [], marker: {cmax: 0, cmin: 0, color: [], size: [], showscale: true, colorbar: {title: @y_axis_title , titleside: 'right'}}}
    @clusters.each do |cluster|
      points = cluster.cluster_points
      points.each do |point|
        expression[:all][:text] << "<b>#{point.cell_name}</b> [#{cluster.name}]<br>log(TPM) expression: #{@gene.scores[point.cell_name].to_f}".html_safe
        expression[:all][:x] << point.x
        expression[:all][:y] << point.y
        # load in expression score to use as color value
        expression[:all][:marker][:color] << @gene.scores[point.cell_name].to_f
        expression[:all][:marker][:line] = { color: 'rgb(40,40,40)', width: 0.5}
        expression[:all][:marker][:size] << 6
      end
    end
    expression
  end

  # load boxplot expression scores with average of scores across each gene for all cells
  def load_gene_set_expression_boxplot_scores
    values = {}
    @clusters.each do |cluster|
      values[cluster.name] = {y: [], name: cluster.name }
      # grab all cells present in the cluster, and use as keys to load expression scores
      # if a cell is not present for the gene, score gets set as 0.0
      cluster.single_cells.map(&:name).each do |cell|
        values[cluster.name][:y] << calculate_mean(@genes, cell)
      end
    end
    values
  end

  # load scatter expression scores with average of scores across each gene for all cells
  def load_gene_set_expression_scatter_points
    expression = {}

    expression[:all] = {x: [], y: [], text: [], marker: {cmax: 0, cmin: 0, size: [], color: [], showscale: true, colorbar: {title: @y_axis_title, titleside: 'right'}}}
    @clusters.each do |cluster|
      points = cluster.cluster_points
      points.each do |point|
        score = calculate_mean(@genes, point.cell_name)
        expression[:all][:text] << "<b>#{point.cell_name}</b> [#{cluster.name}]<br>avg log(TPM) expression: #{score}".html_safe
        expression[:all][:x] << point.x
        expression[:all][:y] << point.y
        # load in expression score to use as color value
        expression[:all][:marker][:color] << score
        expression[:all][:marker][:line] = { color: 'rgb(40,40,40)', width: 0.5}
        expression[:all][:marker][:size] << 6
      end
    end
    expression
  end

  # find mean of expression scores for a given cell
  def calculate_mean(genes, cell)
    sum = 0.0
    genes.each do |gene|
      sum += gene.scores[cell].to_f
    end
    sum / genes.size
  end

  # set the current study
  def set_study
    @study = Study.where(url_safe_name: params[:study_name]).first
  end

  # return clusters, depending on whether top- or sub-level clusters are requested
  def set_clusters
    @clusters = params[:cluster] ? @study.clusters.sub_cluster(params[:cluster]) : @study.clusters.parent_clusters
    @clusters.sort_by!(&:name)
  end

  # generic search term parser
  def parse_search_terms(key)
    terms = params[:search][key]
    if terms.is_a?(Array)
      terms.first.split(/[\s\n,]/).map {|gene| gene.chomp.downcase}
    else
      terms.split(/[\s\n,]/).map {|gene| gene.chomp.downcase}
    end
  end

  # generic expression score getter, preserves order and discards empty matches
  def load_expression_scores(terms)
    genes = []
    terms.each do |term|
      g = @study.expression_scores.by_searchable_gene(term)
      genes << g unless g.nil?
    end
    genes
  end

  # search genes and save terms not found
  def search_expression_scores(terms)
    genes = []
    not_found = []
    terms.each do |term|
      gene = @study.expression_scores.by_searchable_gene(term)
      unless gene.nil?
        genes << gene
      else
        not_found << term
      end
    end
    [genes, not_found]
  end

  # generic method to assemble options for sub-cluster dropdown
  def load_sub_cluster_options
    opts = [["All cell types",""]]
    @study.clusters.parent_clusters.sort_by(&:name).each do |cluster|
      unless @study.clusters.sub_cluster(cluster.name).empty?
        opts << cluster.name
      end
    end
    opts
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
end
