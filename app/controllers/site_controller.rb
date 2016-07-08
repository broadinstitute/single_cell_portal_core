class SiteController < ApplicationController

  respond_to :html, :js

  before_action :set_study, except: :index
  before_action :load_precomputed_options, except: :index
  before_action :set_clusters, except: [:index, :view_all_gene_expression_heatmap, :precomputed_results]

  COLORSCALE_THEMES = ['Blackbody', 'Bluered', 'Blues', 'Earth', 'Electric', 'Greens', 'Hot', 'Jet', 'Picnic', 'Portland', 'Rainbow', 'RdBu', 'Reds', 'Viridis', 'YlGnBu', 'YlOrRd']

  # view study overviews and downloads
  def index
    if user_signed_in?
      @studies = Study.viewable(current_user).sort_by(&:name)
    else
      @studies = Study.where(public: true).order('name ASC')
    end
  end

  # load single study and view top-level clusters
  def study
    # parse all coordinates out into hash using generic method
    @coordinates = load_cluster_points
    @options = load_sub_cluster_options
    @range = set_range(@coordinates.values)
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
      @genes = ExpressionScore.where(:study_id => @study._id, :searchable_gene.in => terms).to_a
    else
      geneset_file = params[:search][:upload]
      terms = geneset_file.read.split(/[\s\n,]/).map {|gene| gene.chomp.downcase}
      @genes = ExpressionScore.where(:study_id => @study._id, :searchable_gene.in => terms).to_a
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
    @gene = ExpressionScore.where(gene: params[:gene]).first
    @y_axis_title = 'log(TPM) Expression Values'
    @values = load_expression_boxplot_scores
    @coordinates = load_cluster_points
    @annotations = load_cluster_annotations
    @expression = load_expression_scatter_points
    color_minmax =  @expression[:all][:marker][:color].minmax
    @expression[:all][:marker][:cmin], @expression[:all][:marker][:cmax] = color_minmax
    @expression[:all][:marker][:colorscale] = 'Reds'
    @options = load_sub_cluster_options
    @range = set_range([@expression[:all]])
    @static_range = set_range(@coordinates.values)
  end

  # re-renders plots when changing cluster selection
  def render_gene_expression_plots
    @gene = ExpressionScore.where(gene: params[:gene]).first
    @y_axis_title = 'log(TPM) Expression Values'
    @values = load_expression_boxplot_scores
    @coordinates = load_cluster_points
    @annotations = load_cluster_annotations
    @expression = load_expression_scatter_points
    color_minmax =  @expression[:all][:marker][:color].minmax
    @expression[:all][:marker][:cmin], @expression[:all][:marker][:cmax] = color_minmax
    @expression[:all][:marker][:colorscale] = 'Reds'
    @options = load_sub_cluster_options
    @range = set_range([@expression[:all]])
    @static_range = set_range(@coordinates.values)
  end

  # view set of genes (scores averaged) as box and scatter plots
  def view_gene_set_expression
    precomputed = PrecomputedScore.where(study_id: @study._id, name: params[:gene_set]).first
    @genes = []
    precomputed.gene_list.map {|gene| @genes << ExpressionScore.find_by(gene: gene)}
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
    render 'view_gene_expression'
  end

  # re-renders plots when changing cluster selection
  def render_gene_set_expression_plots
    precomputed = PrecomputedScore.where(study_id: @study._id, name: params[:gene_set]).first
    @genes = []
    precomputed.gene_list.map {|gene| @genes << ExpressionScore.find_by(gene: gene)}
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
  end

  # load data in gct form to render in Morpheus
  def expression_query
    terms = parse_search_terms(:genes)
    @genes = ExpressionScore.where(:study_id => @study._id, :searchable_gene.in => terms).to_a
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
    @precomputed_score = PrecomputedScore.where(name: params[:precomputed]).first

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
    @precomputed_score = PrecomputedScore.where(study_id: @study._id, name: params[:precomputed]).first
  end

  private

  # generic method to populate data structure to render a cluster scatterplot
  def load_cluster_points
    coordinates = {}
    @clusters.each do |cluster|
      coordinates[cluster.name] = {x: [], y: [], text: [], name: "#{cluster.name}  (#{cluster.cluster_points.size} points)"}
      points = cluster.cluster_points
      points.each do |point|
        coordinates[cluster.name][:text] << "#{point.single_cell.name} <br>[#{cluster.name}]"
        coordinates[cluster.name][:x] << point.x
        coordinates[cluster.name][:y] << point.y
      end
    end
    coordinates
  end

  # loads annotations array if being used for reference plot
  def load_cluster_annotations
    annotations = []
    @clusters.each do |cluster|
      # calculate median position for cluster labels
      x_postions = cluster.cluster_points.map(&:x).sort
      y_postions = cluster.cluster_points.map(&:y).sort
      x_len = x_postions.size
      y_len = y_postions.size
      x_pos = (x_postions[(x_len - 1) / 2] + x_postions[x_len / 2]) / 2.0
      y_pos = (y_postions[(y_len - 1) / 2] + y_postions[y_len / 2]) / 2.0
      annotations << {
          x: x_pos,
          y: y_pos,
          xref: 'x',
          yref: 'y',
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

    expression[:all] = {x: [], y: [], text: [], marker: {cmax: 0, cmin: 0, color: [], showscale: true, colorbar: {title: @y_axis_title , titleside: 'right'}}}
    @clusters.each do |cluster|
      points = cluster.cluster_points
      points.each do |point|
        expression[:all][:text] << "<b>#{point.single_cell.name}</b> [#{cluster.name}]<br>log(TPM) expression: #{@gene.scores[point.single_cell.name].to_f}".html_safe
        expression[:all][:x] << point.x
        expression[:all][:y] << point.y
        # load in expression score to use as color value
        expression[:all][:marker][:color] << @gene.scores[point.single_cell.name].to_f
        expression[:all][:marker][:line] = { color: 'rgb(40,40,40)', width: 0.5}
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

    expression[:all] = {x: [], y: [], text: [], marker: {cmax: 0, cmin: 0, color: [], showscale: true, colorbar: {title: @y_axis_title, titleside: 'right'}}}
    @clusters.each do |cluster|
      points = cluster.cluster_points
      points.each do |point|
        score = calculate_mean(@genes, point.single_cell.name)
        expression[:all][:text] << "<b>#{point.single_cell.name}</b> [#{cluster.name}]<br>avg log(TPM) expression: #{score}".html_safe
        expression[:all][:x] << point.x
        expression[:all][:y] << point.y
        # load in expression score to use as color value
        expression[:all][:marker][:color] << score
        expression[:all][:marker][:line] = { color: 'rgb(40,40,40)', width: 0.5}
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
    params[:search][key].split(/[\s\n,]/).map {|gene| gene.chomp.downcase}
  end

  # search genes and save terms not found
  def search_expression_scores(terms)
    genes = []
    not_found = []
    terms.each do |term|
      gene = ExpressionScore.where(study_id: @study._id, searchable_gene: term).first
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
