class SiteController < ApplicationController
  ###
  #
  # This is the main public controller for the portal.  All data viewing/rendering is handled here, including creating
  # UserAnnotations and submitting workflows.
  #
  ###

  ###
  #
  # FILTERS & SETTINGS
  #
  ###

  respond_to :html, :js, :json

  before_action :set_study, except: [:index, :search, :legacy_study, :get_viewable_studies, :search_all_genes, :privacy_policy, :terms_of_service,
                                     :view_workflow_wdl, :log_action, :get_taxon, :get_taxon_assemblies, :covid19]
  before_action :set_cluster_group, only: [:study, :render_gene_expression_plots, :render_global_gene_expression_plots,
                                           :render_gene_set_expression_plots, :view_gene_expression, :view_gene_set_expression,
                                           :view_gene_expression_heatmap, :view_precomputed_gene_expression_heatmap, :expression_query,
                                           :annotation_query, :get_new_annotations, :annotation_values, :show_user_annotations_form]
  before_action :set_selected_annotation, only: [:render_gene_expression_plots, :render_global_gene_expression_plots,
                                                 :render_gene_set_expression_plots, :view_gene_expression, :view_gene_set_expression,
                                                 :view_gene_expression_heatmap, :view_precomputed_gene_expression_heatmap, :annotation_query,
                                                 :annotation_values, :show_user_annotations_form]
  before_action :load_precomputed_options, only: [:study, :update_study_settings, :render_gene_expression_plots,
                                                  :render_gene_set_expression_plots, :view_gene_expression, :view_gene_set_expression,
                                                  :view_gene_expression_heatmap, :view_precomputed_gene_expression_heatmap]
  before_action :check_view_permissions, except: [:index, :legacy_study, :get_viewable_studies, :search_all_genes, :render_global_gene_expression_plots, :privacy_policy,
                                                  :terms_of_service, :search, :precomputed_results, :expression_query, :annotation_query, :view_workflow_wdl,
                                                  :log_action, :get_workspace_samples, :update_workspace_samples,
                                                  :get_workflow_options, :get_taxon, :get_taxon_assemblies, :covid19, :record_download_acceptance]
  before_action :check_compute_permissions, only: [:get_fastq_files, :get_workspace_samples, :update_workspace_samples,
                                                   :delete_workspace_samples, :get_workspace_submissions, :create_workspace_submission,
                                                   :get_submission_workflow, :abort_submission_workflow, :get_submission_errors,
                                                   :get_submission_outputs, :delete_submission_files, :get_submission_metadata]
  before_action :check_study_detached, only: [:download_file, :update_study_settings,
                                              :get_fastq_files, :get_workspace_samples, :update_workspace_samples,
                                              :delete_workspace_samples, :get_workspace_submissions, :create_workspace_submission,
                                              :get_submission_workflow, :abort_submission_workflow, :get_submission_errors,
                                              :get_submission_outputs, :delete_submission_files, :get_submission_metadata]

  # caching
  caches_action :render_gene_expression_plots, :render_gene_set_expression_plots, :render_global_gene_expression_plots,
                :expression_query, :annotation_query, :precomputed_results,
                cache_path: :set_cache_path
  COLORSCALE_THEMES = %w(Greys YlGnBu Greens YlOrRd Bluered RdBu Reds Blues Picnic Rainbow Portland Jet Hot Blackbody Earth Electric Viridis Cividis)

  ###
  #
  # HOME & SEARCH METHODS
  #
  ###

  # view study overviews/descriptions
  def index
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
    @viewable = Study.viewable(current_user).order_by(@order)

    # filter list if in branding group mode
    if @selected_branding_group.present?
      @viewable = @viewable.where(branding_group_id: @selected_branding_group.id)
    end

    # determine study/cell count based on viewable to user
    @study_count = @viewable.count
    @cell_count = @viewable.map(&:cell_count).inject(&:+)

    if @cell_count.nil?
      @cell_count = 0
    end

    page_num = RequestUtils.sanitize_page_param(params[:page])
    # if search params are present, filter accordingly
    if !params[:search_terms].blank?
      search_terms = sanitize_search_values(params[:search_terms])
      # determine if search values contain possible study accessions
      possible_accessions = StudyAccession.sanitize_accessions(search_terms.split)
      @studies = @viewable.any_of({:$text => {:$search => search_terms}}, {:accession.in => possible_accessions}).
          paginate(page: page_num, per_page: Study.per_page)
    else
      @studies = @viewable.paginate(page: page_num, per_page: Study.per_page)
    end
  end

  def covid
    # nothing for now
  end

  # search for matching studies
  def search
    params[:search_terms] = sanitize_search_values(params[:search_terms])
    # use built-in MongoDB text index (supports quoting terms & case sensitivity)
    @studies = Study.where({'$text' => {'$search' => params[:search_terms]}})

    # restrict to branding group if present
    if @selected_branding_group.present?
      @studies = @studies.where(branding_group_id: @selected_branding_group.id)
    end

    render 'index'
  end

  # legacy method to load a study by url_safe_name, or simply by accession
  def legacy_study
    study = Study.any_of({url_safe_name: params[:identifier]},{accession: params[:identifier]}).first
    if study.present?
      redirect_to merge_default_redirect_params(view_study_path(accession: study.accession,
                                                                study_name: study.url_safe_name,
                                                                scpbr: params[:scpbr])) and return
    else
      redirect_to merge_default_redirect_params(site_path, scpbr: params[:scpbr]),
                  alert: "You either do not have permission to perform that action, or #{params[:identifier]} does not exist." and return
    end
  end

  def privacy_policy

  end

  def terms_of_service

  end

  # redirect handler to determine which gene expression method to render
  def search_genes
    @terms = parse_search_terms(:genes)
    # limit gene search for performance reasons
    if @terms.size > StudySearchService::MAX_GENE_SEARCH
      @terms = @terms.take(StudySearchService::MAX_GENE_SEARCH)
      search_message = StudySearchService::MAX_GENE_SEARCH_MSG
    end
    # grab saved params for loaded cluster, boxpoints mode, annotations, consensus and other view settings
    cluster = params[:search][:cluster]
    annotation = params[:search][:annotation]
    boxpoints = params[:search][:boxpoints]
    consensus = params[:search][:consensus]
    subsample = params[:search][:subsample]
    plot_type = params[:search][:plot_type]
    heatmap_row_centering = params[:search][:heatmap_row_centering]
    heatmap_size = params[:search][:heatmap_size]
    colorscale = params[:search][:colorscale]

    # if only one gene was searched for, make an attempt to load it and redirect to correct page
    if @terms.size == 1
      # do a quick presence check to make sure the gene exists before trying to load
      file_ids = load_study_expression_matrix_ids(@study.id)
      if !Gene.study_has_gene?(study_id: @study.id, expr_matrix_ids: file_ids, gene_name: @terms.first)
        redirect_to merge_default_redirect_params(request.referrer, scpbr: params[:scpbr]),
                    alert: "No matches found for: #{@terms.first}." and return
      else
        redirect_to merge_default_redirect_params(view_gene_expression_path(accession: @study.accession, study_name: @study.url_safe_name, gene: @terms.first,
                                                                            cluster: cluster, annotation: annotation, consensus: consensus,
                                                                            subsample: subsample, plot_type: plot_type,
                                                                            boxpoints: boxpoints, heatmap_row_centering: heatmap_row_centering,
                                                                            heatmap_size: heatmap_size, colorscale: colorscale),
                                                  scpbr: params[:scpbr])  and return
      end
    end

    # else, determine which view to load (heatmaps vs. violin/scatter)
    if !consensus.blank?
      redirect_to merge_default_redirect_params(view_gene_set_expression_path(accession: @study.accession, study_name: @study.url_safe_name,
                                                                              search: {genes: @terms.join(' ')},
                                                                              cluster: cluster, annotation: annotation,
                                                                              consensus: consensus, subsample: subsample,
                                                                              plot_type: plot_type,  boxpoints: boxpoints,
                                                                              heatmap_row_centering: heatmap_row_centering,
                                                                              heatmap_size: heatmap_size, colorscale: colorscale),
                                                scpbr: params[:scpbr]), notice: search_message
    else
      redirect_to merge_default_redirect_params(view_gene_expression_heatmap_path(accession: @study.accession, study_name: @study.url_safe_name,
                                                                                  search: {genes: @terms.join(' ')}, cluster: cluster,
                                                                                  annotation: annotation, plot_type: plot_type,
                                                                                  boxpoints: boxpoints, heatmap_row_centering: heatmap_row_centering,
                                                                                  heatmap_size: heatmap_size, colorscale: colorscale),
                                                scpbr: params[:scpbr]), notice: search_message
    end
  end

  def get_viewable_studies
    @studies = Study.viewable(current_user)

    # restrict to branding group if present
    if @selected_branding_group.present?
      @studies = @studies.where(branding_group_id: @selected_branding_group.id)
    end
    page_num = RequestUtils.sanitize_page_param(params[:page])
    # restrict studies to initialized only
    @studies = @studies.where(initialized: true).paginate(page: page_num, per_page: Study.per_page)
  end

  # global gene search, will return a list of studies that contain the requested gene(s)
  # results will be visualized on a per-gene basis (not merged)
  def search_all_genes
    # set study
    @study = Study.find(params[:id])
    if check_xhr_view_permissions
      # parse and sanitize gene terms
      delim = params[:search][:genes].include?(',') ? ',' : ' '
      raw_genes = params[:search][:genes].split(delim)
      @genes = sanitize_search_values(raw_genes).split(',').map(&:strip)
      # limit gene search for performance reasons
      if @genes.size > StudySearchService::MAX_GENE_SEARCH
        @genes = @genes.take(StudySearchService::MAX_GENE_SEARCH)
      end
      @results = []
      if !@study.initialized?
        head 422
      else
        matrix_ids = @study.expression_matrix_files.map(&:id)
        @genes.each do |gene|
          # determine if study contains requested gene
          matches = @study.genes.any_of({name: gene, :study_file_id.in => matrix_ids},
                                        {searchable_name: gene.downcase, :study_file_id.in => matrix_ids},
                                        {gene_id: gene, :study_file.in => matrix_ids})
          if matches.present?
            matches.each do |match|
              # gotcha where you can have duplicate genes that came from different matrices - ignore these as data is merged on load
              if @results.detect {|r| r.study == match.study && r.searchable_name == match.searchable_name}
                next
              else
                @results << match
              end
            end
          end
        end
      end
    else
      head 403
    end
  end

  ###
  #
  # STUDY SETTINGS
  #
  ###

  # re-render study description as CKEditor instance
  def edit_study_description

  end

  # update selected attributes via study settings tab
  def update_study_settings
    @spinner_target = '#update-study-settings-spinner'
    @modal_target = '#update-study-settings-modal'
    if !user_signed_in?
      set_study_default_options
      @notice = 'Please sign in before continuing.'
      render action: 'notice'
    else
      if @study.can_edit?(current_user)
        if @study.update(study_params)
          # invalidate caches as a precaution
          CacheRemovalJob.new(@study.accession).delay(queue: :cache).perform
          if @study.initialized?
            @cluster = @study.default_cluster
            @options = ClusterVizService.load_cluster_group_options(@study)
            @cluster_annotations = ClusterVizService.load_cluster_group_annotations(@study, @cluster, current_user)
            set_selected_annotation
          end

          # double check on download availability: first, check if administrator has disabled downloads
          # then check if FireCloud is available and disable download links if either is true
          @allow_downloads = ApplicationController.firecloud_client.services_available?(FireCloudClient::BUCKETS_SERVICE)
        end
        set_firecloud_permissions(@study.detached?)
        set_study_permissions(@study.detached?)
        set_study_default_options
        set_study_download_options
      else
        set_study_default_options
        @alert = 'You do not have permission to perform that action.'
        render action: 'notice'
      end
    end
  end

  ###
  #
  # VIEW/RENDER METHODS
  #
  ###

  ## CLUSTER-BASED

  # load single study and view top-level clusters
  def study
    @study.update(view_count: @study.view_count + 1)
    @unique_genes = @study.unique_genes
    @taxons = @study.expressed_taxon_names

    # set general state of study to enable various tabs in UI
    # double check on download availability: first, check if administrator has disabled downloads
    # then check individual statuses to see what to enable/disable
    # if the study is 'detached', then everything is set to false by default
    set_firecloud_permissions(@study.detached?)
    set_study_permissions(@study.detached?)
    set_study_default_options
    set_study_download_options

    # load options and annotations
    if @study.can_visualize_clusters?
      @options = ClusterVizService.load_cluster_group_options(@study)
      @cluster_annotations = ClusterVizService.load_cluster_group_annotations(@study, @cluster, current_user)
      # call set_selected_annotation manually
      set_selected_annotation
    end

    # only populate if study has ideogram results & is not 'detached'
    if @study.has_analysis_outputs?('infercnv', 'ideogram.js') && !@study.detached?
      @ideogram_files = {}
      @study.get_analysis_outputs('infercnv', 'ideogram.js').each do |file|
        opts = file.options.with_indifferent_access # allow lookup by string or symbol
        cluster_name = opts[:cluster_name]
        annotation_name = opts[:annotation_name].split('--').first
        @ideogram_files[file.id.to_s] = {
            cluster: cluster_name,
            annotation: opts[:annotation_name],
            display: "#{cluster_name}: #{annotation_name}",
            ideogram_settings: @study.get_ideogram_infercnv_settings(cluster_name, opts[:annotation_name])
        }
      end
    end

    if @allow_firecloud_access && @user_can_compute
      # load list of previous submissions
      workspace = ApplicationController.firecloud_client.get_workspace(@study.firecloud_project, @study.firecloud_workspace)
      @submissions = ApplicationController.firecloud_client.get_workspace_submissions(@study.firecloud_project, @study.firecloud_workspace)

      @submissions.each do |submission|
        update_analysis_submission(submission)
      end
      # remove deleted submissions from list of runs
      if !workspace['workspace']['attributes']['deleted_submissions'].blank?
        deleted_submissions = workspace['workspace']['attributes']['deleted_submissions']['items']
        @submissions.delete_if {|submission| deleted_submissions.include?(submission['submissionId'])}
      end

      # load list of available workflows
      @workflows_list = load_available_workflows
    end
  end

  def record_download_acceptance
    @download_acceptance = DownloadAcceptance.new(download_acceptance_params)
    if @download_acceptance.save
      respond_to do |format|
        format.js
      end
    end
  end

  ## GENE-BASED

  # render violin and scatter plots for parent clusters or a particular sub cluster
  def view_gene_expression
    @options = ClusterVizService.load_cluster_group_options(@study)
    @cluster_annotations = ClusterVizService.load_cluster_group_annotations(@study, @cluster, current_user)
    @top_plot_partial = @selected_annotation[:type] == 'group' ? 'expression_plots_view' : 'expression_annotation_plots_view'
    @y_axis_title = ExpressionVizService.load_expression_axis_title(@study)

    @gene = params[:gene]

    if @study.expressed_taxon_names.length > 1
      @gene_taxons = @study.infer_taxons(@gene)
    else
      @gene_taxons = @study.expressed_taxon_names
    end

    if request.format == 'text/html'
      # only set this check on full page loads (happens if user was not signed in but then clicked the 'genome' tab)
      set_firecloud_permissions(@study.detached?)
      @user_can_edit = @study.can_edit?(current_user)
      @user_can_compute = @study.can_compute?(current_user)
      @user_can_download = @study.can_download?(current_user)
    end
  end

  # re-renders plots when changing cluster selection
  def render_gene_expression_plots
    subsample = params[:subsample].blank? ? nil : params[:subsample].to_i
    @gene = @study.genes.by_name_or_id(params[:gene], @study.expression_matrix_files.map(&:id))
    @y_axis_title = ExpressionVizService.load_expression_axis_title(@study)
    # depending on annotation type selection, set up necessary partial names to use in rendering
    if @selected_annotation[:type] == 'group'
      @values = ExpressionVizService.load_expression_boxplot_data_array_scores(@study, @gene, @cluster,
                                                                               @selected_annotation, subsample)
      if params[:plot_type] == 'box'
        @values_box_type = 'box'
      else
        @values_box_type = 'violin'
        @values_jitter = params[:boxpoints]
      end
      @top_plot_partial = 'expression_plots_view'
      @top_plot_plotly = 'expression_plots_plotly'
      @top_plot_layout = 'expression_box_layout'
    else
      @values = ExpressionVizService.load_annotation_based_data_array_scatter(@study, @gene, @cluster, @selected_annotation,
                                                                              subsample, @y_axis_title)
      @top_plot_partial = 'expression_annotation_plots_view'
      @top_plot_plotly = 'expression_annotation_plots_plotly'
      @top_plot_layout = 'expression_annotation_scatter_layout'
      @annotation_scatter_range = ClusterVizService.set_range(@cluster, @values.values)
    end
    @expression = ExpressionVizService.load_expression_data_array_points(@study, @gene, @cluster, @selected_annotation,
                                                                         subsample, @y_axis_title, params[:colorscale])
    @options = ClusterVizService.load_cluster_group_options(@study)
    @range = ClusterVizService.set_range(@cluster,[@expression[:all]])
    @coordinates = ClusterVizService.load_cluster_group_data_array_points(@study, @cluster, @selected_annotation, subsample)
    if @cluster.has_coordinate_labels?
      @coordinate_labels = ClusterVizService.load_cluster_group_coordinate_labels(@cluster)
    end
    @static_range = ClusterVizService.set_range(@cluster, @coordinates.values)
    if @cluster.is_3d? && @cluster.has_range?
      @expression_aspect = ClusterVizService.compute_aspect_ratios(@range)
      @static_aspect = ClusterVizService.compute_aspect_ratios(@static_range)
    end
    @cluster_annotations = ClusterVizService.load_cluster_group_annotations(@study, @cluster, current_user)

    # load default color profile if necessary
    if params[:annotation] == @study.default_annotation && @study.default_annotation_type == 'numeric' && !@study.default_color_profile.nil?
      @expression[:all][:marker][:colorscale] = @study.default_color_profile
      @coordinates[:all][:marker][:colorscale] = @study.default_color_profile
    end
  end

  # renders gene expression plots, but from global gene search. uses default annotations on first render, but takes URL parameters after that
  def render_global_gene_expression_plots
    if check_xhr_view_permissions
      subsample = params[:subsample].blank? ? nil : params[:subsample].to_i
      @gene = @study.genes.by_name_or_id(params[:gene], @study.expression_matrix_files.map(&:id))
      @identifier = params[:identifier] # unique identifer for each plot for namespacing JS variables/functions (@gene.id)
      @target = 'study-' + @study.id + '-gene-' + @identifier
      @y_axis_title = ExpressionVizService.load_expression_axis_title(@study)
      if @selected_annotation[:type] == 'group'
        @values = ExpressionVizService.load_expression_boxplot_data_array_scores(@study, @gene, @cluster,
                                                                                 @selected_annotation, subsample)
        @values_jitter = params[:boxpoints]
      else
        @values = ExpressionVizService.load_annotation_based_data_array_scatter(@study, @gene, @cluster, @selected_annotation,
                                                                                subsample, @y_axis_title)
      end
      @options = ClusterVizService.load_cluster_group_options(@study)
      @cluster_annotations = ClusterVizService.load_cluster_group_annotations(@study, @cluster, current_user)
    else
      head 403
    end
  end

  # view set of genes (scores averaged) as box and scatter plots
  # works for both a precomputed list (study supplied) or a user query
  def view_gene_set_expression
    # first check if there is a user-supplied gene list to view as consensus
    # call search_expression_scores to return values not found

    terms = params[:gene_set].blank? && !params[:consensus].blank? ? parse_search_terms(:genes) : @study.precomputed_scores.by_name(params[:gene_set]).gene_list
    @genes, @not_found = search_expression_scores(terms, @study.id)

    consensus = params[:consensus].nil? ? 'Mean ' : params[:consensus].capitalize + ' '
    @gene_list = @genes.map{|gene| gene['name']}.join(' ')
    @y_axis_title = consensus + ' ' + ExpressionVizService.load_expression_axis_title(@study)
    # depending on annotation type selection, set up necessary partial names to use in rendering
    @options = ClusterVizService.load_cluster_group_options(@study)
    @cluster_annotations = ClusterVizService.load_cluster_group_annotations(@study, @cluster, current_user)
    @top_plot_partial = @selected_annotation[:type] == 'group' ? 'expression_plots_view' : 'expression_annotation_plots_view'

    if @genes.size > 5
      @main_genes, @other_genes = divide_genes_for_header
    end
    # make sure we found genes, otherwise redirect back to base view
    if @genes.empty?
      redirect_to merge_default_redirect_params(view_study_path(accession: @study.accession, study_name: @study.url_safe_name), scpbr: params[:scpbr]), alert: "None of the requested genes were found: #{terms.join(', ')}"
    else
      render 'view_gene_expression'
    end
  end

  # re-renders plots when changing cluster selection
  def render_gene_set_expression_plots
    # first check if there is a user-supplied gene list to view as consensus
    # call load expression scores since we know genes exist already from view_gene_set_expression

    terms = params[:gene_set].blank? ? parse_search_terms(:genes) : @study.precomputed_scores.by_name(params[:gene_set]).gene_list
    @genes = load_expression_scores(terms)
    subsample = params[:subsample].blank? ? nil : params[:subsample].to_i
    consensus = params[:consensus].nil? ? 'Mean ' : params[:consensus].capitalize + ' '
    @gene_list = @genes.map{|gene| gene['gene']}.join(' ')
    dotplot_genes, dotplot_not_found = search_expression_scores(terms, @study.id)
    @dotplot_gene_list = dotplot_genes.map{|gene| gene['name']}.join(' ')
    @y_axis_title = consensus + ' ' + ExpressionVizService.load_expression_axis_title(@study)
    # depending on annotation type selection, set up necessary partial names to use in rendering
    if @selected_annotation[:type] == 'group'
      @values = ExpressionVizService.load_gene_set_expression_boxplot_scores(@study, @genes, @cluster, @selected_annotation,
                                                                             params[:consensus], subsample)
      if params[:plot_type] == 'box'
        @values_box_type = 'box'
      else
        @values_box_type = 'violin'
        @values_jitter = params[:jitter]
      end
      @top_plot_partial = 'expression_plots_view'
      @top_plot_plotly = 'expression_plots_plotly'
      @top_plot_layout = 'expression_box_layout'
    else
      @values = ExpressionVizService.load_gene_set_annotation_based_scatter(@study, @genes, @cluster, @selected_annotation,
                                                                            params[:consensus], subsample, @y_axis_title)
      @top_plot_partial = 'expression_annotation_plots_view'
      @top_plot_plotly = 'expression_annotation_plots_plotly'
      @top_plot_layout = 'expression_annotation_scatter_layout'
      @annotation_scatter_range = ClusterVizService.set_range(@cluster, @values.values)
    end
    # load expression scatter using main gene expression values
    @expression = ExpressionVizService.load_gene_set_expression_data_arrays(@study, @genes, @cluster, @selected_annotation,
                                                                            params[:consensus], subsample, @y_axis_title,
                                                                            params[:colorscale])
    @expression[:all][:marker][:cmin], @expression[:all][:marker][:cmax] = RequestUtils.get_minmax(@expression[:all][:marker][:color])

    # load static cluster reference plot
    @coordinates = ClusterVizService.load_cluster_group_data_array_points(@study, @cluster, @selected_annotation, subsample)
    # set up options, annotations and ranges
    @options = ClusterVizService.load_cluster_group_options(@study)
    @range = ClusterVizService.set_range(@cluster,[@expression[:all]])
    @static_range = ClusterVizService.set_range(@cluster, @coordinates.values)

    if @cluster.is_3d? && @cluster.has_range?
      @expression_aspect = ClusterVizService.compute_aspect_ratios(@range)
      @static_aspect = ClusterVizService.compute_aspect_ratios(@static_range)
    end

    @cluster_annotations = ClusterVizService.load_cluster_group_annotations(@study, @cluster, current_user)

    if @genes.size > 5
      @main_genes, @other_genes = divide_genes_for_header
    end

    # load default color profile if necessary
    if params[:annotation] == @study.default_annotation && @study.default_annotation_type == 'numeric' && !@study.default_color_profile.nil?
      @expression[:all][:marker][:colorscale] = @study.default_color_profile
      @coordinates[:all][:marker][:colorscale] = @study.default_color_profile
    end

    render 'render_gene_expression_plots'
  end

  # view genes in Morpheus as heatmap
  def view_gene_expression_heatmap
    # parse and divide up genes
    terms = parse_search_terms(:genes)
    @genes, @not_found = search_expression_scores(terms, @study.id)
    @gene_list = @genes.map{|gene| gene['name']}.join(' ')
    # load dropdown options
    @options = ClusterVizService.load_cluster_group_options(@study)
    @cluster_annotations = ClusterVizService.load_cluster_group_annotations(@study, @cluster, current_user)
    if @genes.size > 5
      @main_genes, @other_genes = divide_genes_for_header
    end
    # make sure we found genes, otherwise redirect back to base view
    if @genes.empty?
      redirect_to merge_default_redirect_params(view_study_path(accession: @study.accession, study_name: @study.url_safe_name), scpbr: params[:scpbr]), alert: "None of the requested genes were found: #{terms.join(', ')}"
    end
  end

  # load data in gct form to render in Morpheus, preserving query order
  def expression_query
    if check_xhr_view_permissions
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
        row = [gene['name'], ""]
        case params[:row_centered]
          when 'z-score'
            vals = Gene.z_score(gene['scores'], @cells)
            row += vals
          when 'robust-z-score'
            vals = Gene.robust_z_score(gene['scores'], @cells)
            row += vals
          else
            @cells.each do |cell|
              row << gene['scores'][cell].to_f
            end
        end
        @rows << row.join("\t")
      end
      @data = ['#1.2', [@rows.size, @cols].join("\t"), @headers.join("\t"), @rows.join("\n")].join("\n")

      send_data @data, type: 'text/plain'
    else
      head 403
    end
  end

  # load annotations in tsv format for Morpheus
  def annotation_query
    if check_xhr_view_permissions
      @cells = @cluster.concatenate_data_arrays('text', 'cells')
      if @selected_annotation[:scope] == 'cluster'
        @annotations = @cluster.concatenate_data_arrays(@selected_annotation[:name], 'annotations')
      else
        study_annotations = @study.cell_metadata_values(@selected_annotation[:name], @selected_annotation[:type])
        @annotations = []
        @cells.each do |cell|
          @annotations << study_annotations[cell]
        end
      end
      # assemble rows of data
      @rows = []
      @cells.each_with_index do |cell, index|
        @rows << [cell, @annotations[index]].join("\t")
      end
      @headers = ['NAME', @selected_annotation[:name]]
      @data = [@headers.join("\t"), @rows.join("\n")].join("\n")
      send_data @data, type: 'text/plain'
    else
      head 403
    end
  end

  # dynamically reload cluster-based annotations list when changing clusters
  def get_new_annotations
    @cluster_annotations = ClusterVizService.load_cluster_group_annotations(@study, @cluster, current_user)
    @target = params[:target].blank? ? nil : params[:target] + '-'
    # used to match value of previous annotation with new values
    @flattened_annotations = @cluster_annotations.values.map {|coll| coll.map(&:last)}.flatten
  end

  # return JSON representation of selected annotation
  def annotation_values
    render json: @selected_annotation.to_json
  end

  ## GENELIST-BASED

  # load precomputed data in gct form to render in Morpheus
  def precomputed_results
    if check_xhr_view_permissions
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
    else
      head 403
    end
  end

  # redirect to show precomputed marker gene results
  def search_precomputed_results
    redirect_to merge_default_redirect_params(view_precomputed_gene_expression_heatmap_path(accession: params[:accession],
                                                                                            study_name: params[:study_name],
                                                                                            precomputed: params[:expression]),
                                              scpbr: params[:scpbr])
  end

  # view all genes as heatmap in morpheus, will pull from pre-computed gct file
  def view_precomputed_gene_expression_heatmap
    @precomputed_score = @study.precomputed_scores.by_name(params[:precomputed])
    @options = ClusterVizService.load_cluster_group_options(@study)
    @cluster_annotations = ClusterVizService.load_cluster_group_annotations(@study, @cluster, current_user)
  end

  ###
  #
  # DOWNLOAD METHODS
  #
  ###

  # method to download files if study is public
  def download_file
    # verify user can download file
    verify_file_download_permissions(@study); return if performed?
    # initiate file download action
    execute_file_download(@study); return if performed?
  end


  ###
  #
  # ANNOTATION METHODS
  #
  ###

  # render the 'Create Annotations' form (must be done via ajax to get around page caching issues)
  def show_user_annotations_form

  end

  ###
  #
  # WORKFLOW METHODS
  #
  ###

  # method to populate an array with entries corresponding to all fastq files for a study (both owner defined as study_files
  # and extra fastq's that happen to be in the bucket)
  def get_fastq_files
    @fastq_files = []
    file_list = []

    #
    selected_entries = params[:selected_entries].split(',').map(&:strip)
    selected_entries.each do |entry|
      class_name, entry_name = entry.split('--')
      case class_name
        when 'directorylisting'
          directory = @study.directory_listings.are_synced.detect {|d| d.name == entry_name}
          if !directory.nil?
            directory.files.each do |file|
              entry = file
              entry[:gs_url] = directory.gs_url(file[:name])
              file_list << entry
            end
          end
        when 'studyfile'
          study_file = @study.study_files.by_type('Fastq').detect {|f| f.name == entry_name}
          if !study_file.nil?
            file_list << {name: study_file.bucket_location, size: study_file.upload_file_size, generation: study_file.generation, gs_url: study_file.gs_url}
          end
        else
          nil # this is called when selection is cleared out
      end
    end
    # now that we have the complete list, populate the table with sample pairs (if present)
    populate_rows(@fastq_files, file_list)

    render json: @fastq_files.to_json
  end

  # view the wdl of a specified workflow
  def view_workflow_wdl
    analysis_configuration = AnalysisConfiguration.find_by(namespace: params[:namespace], name: params[:workflow],
                                                                              snapshot: params[:snapshot].to_i)
    @workflow_name = analysis_configuration.name
    @workflow_wdl = analysis_configuration.wdl_payload
  end

  # get the available entities for a workspace
  def get_workspace_samples
    begin
      requested_samples = params[:samples].split(',')
      # get all samples
      all_samples = ApplicationController.firecloud_client.get_workspace_entities_by_type(@study.firecloud_project, @study.firecloud_workspace, 'sample')
      # since we can't query the API (easily) for matching samples, just get all and then filter based on requested samples
      matching_samples = all_samples.keep_if {|sample| requested_samples.include?(sample['name']) }
      @samples = []
      matching_samples.each do |sample|
        @samples << [sample['name'],
                     sample['attributes']['fastq_file_1'],
                     sample['attributes']['fastq_file_2'],
                     sample['attributes']['fastq_file_3'],
                     sample['attributes']['fastq_file_4']
        ]
      end
      render json: @samples.to_json
    rescue => e
      error_context = ErrorTracker.format_extra_context(@study, {params: params})
      ErrorTracker.report_exception(e, current_user, error_context)
      MetricsService.report_error(e, request, current_user, @study)
      logger.error "Error retrieving workspace samples for #{study.name}; #{e.message}"
      render json: []
    end
  end

  # save currently selected sample information back to study workspace
  def update_workspace_samples
    form_payload = params[:samples]

    begin
      # create a 'real' temporary file as we can't pass open tempfiles
      filename = "#{SecureRandom.uuid}-sample-info.tsv"
      temp_tsv = File.new(Rails.root.join('data', @study.data_dir, filename), 'w+')

      # add participant_id to new file as FireCloud data model requires this for samples (all samples get default_participant value)
      headers = %w(entity:sample_id participant_id fastq_file_1 fastq_file_2 fastq_file_3 fastq_file_4)
      temp_tsv.write headers.join("\t") + "\n"

      # get list of samples from form payload
      samples = form_payload.keys
      samples.each do |sample|
        # construct a new line to write to the tsv file
        newline = "#{sample}\tdefault_participant\t"
        vals = []
        headers[2..5].each do |attr|
          # add a value for each parameter, created an empty string if this was not present in the form data
          vals << form_payload[sample][attr].to_s
        end
        # write new line to tsv file
        newline += vals.join("\t")
        temp_tsv.write newline + "\n"
      end
      # close the file to ensure write is completed
      temp_tsv.close

      # now reopen and import into FireCloud
      upload = File.open(temp_tsv.path)
      ApplicationController.firecloud_client.import_workspace_entities_file(@study.firecloud_project, @study.firecloud_workspace, upload)

      # upon success, load the newly imported samples from the workspace and update the form
      new_samples = ApplicationController.firecloud_client.get_workspace_entities_by_type(@study.firecloud_project, @study.firecloud_workspace, 'sample')
      @samples = Naturally.sort(new_samples.map {|s| s['name']})

      # clean up tempfile
      File.delete(temp_tsv.path)

      # render update notice
      @notice = 'Your sample information has successfully been saved.'
      render action: :update_workspace_samples
    rescue => e
      error_context = ErrorTracker.format_extra_context(@study, {params: params})
      ErrorTracker.report_exception(e, current_user, error_context)
      MetricsService.report_error(e, request, current_user, @study)
      logger.info "Error saving workspace entities: #{e.message}"
      @alert = "An error occurred while trying to save your sample information: #{view_context.simple_format(e.message)}"
      render action: :notice
    end
  end

  # delete selected samples from workspace data entities
  def delete_workspace_samples
    samples = params[:samples]
    begin
      # create a mapping of samples to delete
      delete_payload = ApplicationController.firecloud_client.create_entity_map(samples, 'sample')
      ApplicationController.firecloud_client.delete_workspace_entities(@study.firecloud_project, @study.firecloud_workspace, delete_payload)

      # upon success, load the newly imported samples from the workspace and update the form
      new_samples = ApplicationController.firecloud_client.get_workspace_entities_by_type(@study.firecloud_project, @study.firecloud_workspace, 'sample')
      @samples = Naturally.sort(new_samples.map {|s| s['name']})

      # render update notice
      @notice = 'The requested samples have successfully been deleted.'

      # set flag to empty out the samples table to prevent the user from trying to delete the sample again
      @empty_samples_table = true
      render action: :update_workspace_samples
    rescue => e
      error_context = ErrorTracker.format_extra_context(@study, {params: params})
      ErrorTracker.report_exception(e, current_user, error_context)
      MetricsService.report_error(e, request, current_user, @study)
      logger.error "Error deleting workspace entities: #{e.message}"
      @alert = "An error occurred while trying to delete your sample information: #{view_context.simple_format(e.message)}"
      render action: :notice
    end
  end

  # get all submissions for a study workspace
  def get_workspace_submissions
    workspace = ApplicationController.firecloud_client.get_workspace(@study.firecloud_project, @study.firecloud_workspace)
    @submissions = ApplicationController.firecloud_client.get_workspace_submissions(@study.firecloud_project, @study.firecloud_workspace)
    # update any AnalysisSubmission records with new statuses
    @submissions.each do |submission|
      update_analysis_submission(submission)
    end
    # remove deleted submissions from list of runs
    if !workspace['workspace']['attributes']['deleted_submissions'].blank?
      deleted_submissions = workspace['workspace']['attributes']['deleted_submissions']['items']
      @submissions.delete_if {|submission| deleted_submissions.include?(submission['submissionId'])}
    end
  end

  # retrieve analysis configuration and associated parameters
  def get_analysis_configuration
    namespace, name, snapshot = params[:workflow_identifier].split('--')
    @analysis_configuration = AnalysisConfiguration.find_by(namespace: namespace, name: name,
                                                           snapshot: snapshot.to_i)
  end

  def create_workspace_submission
    begin
      # before creating submission, we need to make sure that the user is on the 'all-portal' user group list if it exists
      current_user.add_to_portal_user_group

      # load analysis configuration
      @analysis_configuration = AnalysisConfiguration.find(params[:analysis_configuration_id])


      logger.info "Updating configuration for #{@analysis_configuration.configuration_identifier} to run #{@analysis_configuration.identifier} in #{@study.firecloud_project}/#{@study.firecloud_workspace}"
      submission_config = @analysis_configuration.apply_user_inputs(params[:workflow][:inputs])
      # save configuration in workspace
      ApplicationController.firecloud_client.create_workspace_configuration(@study.firecloud_project, @study.firecloud_workspace, submission_config)

      # submission must be done as user, so create a client with current_user and submit
      client = FireCloudClient.new(current_user, @study.firecloud_project)
      logger.info "Creating submission for #{@analysis_configuration.configuration_identifier} using configuration: #{submission_config['name']} in #{@study.firecloud_project}/#{@study.firecloud_workspace}"
      @submission = client.create_workspace_submission(@study.firecloud_project, @study.firecloud_workspace,
                                                         submission_config['namespace'], submission_config['name'],
                                                         submission_config['entityType'], submission_config['entityName'])
      AnalysisSubmission.create(submitter: current_user.email, study_id: @study.id, firecloud_project: @study.firecloud_project,
                                submission_id: @submission['submissionId'], firecloud_workspace: @study.firecloud_workspace,
                                analysis_name: @analysis_configuration.identifier, submitted_on: Time.zone.now, submitted_from_portal: true)
    rescue => e
      error_context = ErrorTracker.format_extra_context(@study, {params: params})
      ErrorTracker.report_exception(e, current_user, error_context)
      MetricsService.report_error(e, request, current_user, @study)
      logger.error "Unable to submit workflow #{@analysis_configuration.identifier} in #{@study.firecloud_workspace} due to: #{e.message}"
      @alert = "We were unable to submit your workflow due to an error: #{e.message}"
      render action: :notice
    end
  end

  # get a submission workflow object as JSON
  def get_submission_workflow
    begin
      submission = ApplicationController.firecloud_client.get_workspace_submission(@study.firecloud_project, @study.firecloud_workspace, params[:submission_id])
      render json: submission.to_json
    rescue => e
      error_context = ErrorTracker.format_extra_context(@study, {params: params})
      ErrorTracker.report_exception(e, current_user, error_context)
      MetricsService.report_error(e, request, current_user, @study)
      logger.error "Unable to load workspace submission #{params[:submission_id]} in #{@study.firecloud_workspace} due to: #{e.message}"
      render js: "alert('We were unable to load the requested submission due to an error: #{e.message}')"
    end
  end

  # abort a pending workflow submission
  def abort_submission_workflow
    @submission_id = params[:submission_id]
    begin
      ApplicationController.firecloud_client.abort_workspace_submission(@study.firecloud_project, @study.firecloud_workspace, @submission_id)
      @notice = "Submission #{@submission_id} was successfully aborted."
    rescue => e
      error_context = ErrorTracker.format_extra_context(@study, {params: params})
      ErrorTracker.report_exception(e, current_user, error_context)
      MetricsService.report_error(e, request, current_user, @study)
      @alert = "Unable to abort submission #{@submission_id} due to an error: #{e.message}"
      render action: :notice
    end
  end

  # get errors for a failed submission
  def get_submission_errors
    begin
      workflow_ids = params[:workflow_ids].split(',')
      errors = []
      # first check workflow messages - if there was an issue with inputs, errors could be here
      submission = ApplicationController.firecloud_client.get_workspace_submission(@study.firecloud_project, @study.firecloud_workspace, params[:submission_id])
      submission['workflows'].each do |workflow|
        if workflow['messages'].any?
          workflow['messages'].each {|message| errors << message}
        end
      end
      # now look at each individual workflow object
      workflow_ids.each do |workflow_id|
        workflow = ApplicationController.firecloud_client.get_workspace_submission_workflow(@study.firecloud_project, @study.firecloud_workspace, params[:submission_id], workflow_id)
        # failure messages are buried deeply within the workflow object, so we need to go through each to find them
        workflow['failures'].each do |workflow_failure|
          errors << workflow_failure['message']
          # sometimes there are extra errors nested below...
          if workflow_failure['causedBy'].any?
            workflow_failure['causedBy'].each do |failure|
              errors << failure['message']
            end
          end
        end
      end
      @error_message = errors.join("<br />")
    rescue => e
      error_context = ErrorTracker.format_extra_context(@study, {params: params})
      ErrorTracker.report_exception(e, current_user, error_context)
      MetricsService.report_error(e, request, current_user, @study)
      @alert = "Unable to retrieve submission #{@submission_id} error messages due to: #{e.message}"
      render action: :notice
    end
  end

  # get outputs from a requested submission
  def get_submission_outputs
    begin
      @outputs = []
      submission = ApplicationController.firecloud_client.get_workspace_submission(@study.firecloud_project, @study.firecloud_workspace, params[:submission_id])
      submission['workflows'].each do |workflow|
        workflow = ApplicationController.firecloud_client.get_workspace_submission_workflow(@study.firecloud_project, @study.firecloud_workspace, params[:submission_id], workflow['workflowId'])
        workflow['outputs'].each do |output, file_url|
          display_name = file_url.split('/').last
          file_location = file_url.gsub(/gs\:\/\/#{@study.bucket_id}\//, '')
          output = {display_name: display_name, file_location: file_location}
          @outputs << output
        end
      end
    rescue => e
      error_context = ErrorTracker.format_extra_context(@study, {params: params})
      ErrorTracker.report_exception(e, current_user, error_context)
      MetricsService.report_error(e, request, current_user, @study)
      @alert = "Unable to retrieve submission #{@submission_id} outputs due to: #{e.message}"
      render action: :notice
    end
  end

  # retrieve a submission analysis metadata file
  def get_submission_metadata
    begin
      submission = ApplicationController.firecloud_client.get_workspace_submission(@study.firecloud_project, @study.firecloud_workspace, params[:submission_id])
      if submission.present?
        # check to see if we already have an analysis_metadatum object
        @metadata = AnalysisMetadatum.find_by(study_id: @study.id, submission_id: params[:submission_id])
        if @metadata.nil?
          metadata_attr = {
              name: submission['methodConfigurationName'],
              submission_id: params[:submission_id],
              study_id: @study.id,
              version: '4.6.1'
          }
          @metadata = AnalysisMetadatum.create!(metadata_attr)
        end
      else
        @alert = "We were unable to locate submission '#{params[:submission_id]}'.  Please check the ID and try again."
        render action: :notice
      end
    rescue => e
      error_context = ErrorTracker.format_extra_context(@study, {params: params})
      ErrorTracker.report_exception(e, current_user, error_context)
      MetricsService.report_error(e, request, current_user, @study)
      @alert = "An error occurred trying to load submission '#{params[:submission_id]}': #{e.message}"
      render action: :notice
    end
  end

  # export a submission analysis metadata file
  def export_submission_metadata
    @metadata = AnalysisMetadatum.find_by(study_id: @study.id, submission_id: params[:submission_id])
    respond_to do |format|
      format.html {send_data JSON.pretty_generate(@metadata.payload), content_type: :json, filename: 'analysis.json'}
      format.json {render json: @metadata.payload}
    end

  end

  # delete all files from a submission
  def delete_submission_files
    begin
      # first, add submission to list of 'deleted_submissions' in workspace attributes (will hide submission in list)
      workspace = ApplicationController.firecloud_client.get_workspace(@study.firecloud_project, @study.firecloud_workspace)
      ws_attributes = workspace['workspace']['attributes']
      if ws_attributes['deleted_submissions'].blank?
        ws_attributes['deleted_submissions'] = [params[:submission_id]]
      else
        ws_attributes['deleted_submissions']['items'] << params[:submission_id]
      end
      logger.info "Adding #{params[:submission_id]} to workspace delete_submissions attribute in #{@study.firecloud_workspace}"
      ApplicationController.firecloud_client.set_workspace_attributes(@study.firecloud_project, @study.firecloud_workspace, ws_attributes)
      logger.info "Deleting analysis metadata for #{params[:submission_id]} in #{@study.url_safe_name}"
      AnalysisMetadatum.where(submission_id: params[:submission_id]).delete
      logger.info "Queueing submission #{params[:submission]} deletion in #{@study.firecloud_workspace}"
      submission_files = ApplicationController.firecloud_client.execute_gcloud_method(:get_workspace_files, 0, @study.bucket_id, prefix: params[:submission_id])
      DeleteQueueJob.new(submission_files).perform
    rescue => e
      error_context = ErrorTracker.format_extra_context(@study, {params: params})
      ErrorTracker.report_exception(e, current_user, error_context)
      MetricsService.report_error(e, request, current_user, @study)
      logger.error "Unable to remove submission #{params[:submission_id]} files from #{@study.firecloud_workspace} due to: #{e.message}"
      @alert = "Unable to delete the outputs for #{params[:submission_id]} due to the following error: #{e.message}"
      render action: :notice
    end
  end

  ###
  #
  # MISCELLANEOUS METHODS
  #
  ###

  # route that is used to log actions in Google Analytics that would otherwise be ignored due to redirects or response types
  def log_action
    @action_to_log = params[:url_string]
  end

  # get taxon info
  def get_taxon
    @taxon = Taxon.find(params[:taxon])
    render json: @taxon.attributes
  end

  # get GenomeAssembly information for a given Taxon for StudyFile associations and other menu actions
  def get_taxon_assemblies
    @assemblies = []
    taxon = Taxon.find(params[:taxon])
    if taxon.present?
      @assemblies = taxon.genome_assemblies.map {|assembly| [assembly.name, assembly.id.to_s]}
    end
    render json: @assemblies
  end

  private

  ###
  #
  # SETTERS
  #
  ###

  def set_study
    @study = Study.find_by(accession: params[:accession])
        # redirect if study is not found
    if @study.nil?
      redirect_to merge_default_redirect_params(site_path, scpbr: params[:scpbr]),
                  alert: "You either do not have permission to perform that action, or #{params[:accession]} does not exist." and return
    end
        #Check if current url_safe_name matches model
    unless @study.url_safe_name == params[:study_name]
           redirect_to merge_default_redirect_params(view_study_path(accession: params[:accession],
                                                                     study_name: @study.url_safe_name,
                                                                     scpbr:params[:scpbr])) and return
      end

  end

  def set_cluster_group
    @cluster = ClusterVizService.get_cluster_group(@study, params)
  end

  def set_selected_annotation
    annot_params = ExpressionVizService.parse_annotation_legacy_params(@study, params)
    @selected_annotation = AnnotationVizService.get_selected_annotation(
      @study,
      cluster: @cluster,
      annot_name: annot_params[:name],
      annot_type: annot_params[:type],
      annot_scope: annot_params[:scope]
    )
  end

  def set_workspace_samples
    all_samples = ApplicationController.firecloud_client.get_workspace_entities_by_type(@study.firecloud_project, @study.firecloud_workspace, 'sample')
    @samples = Naturally.sort(all_samples.map {|s| s['name']})
    # load locations of primary data (for new sample selection)
    @primary_data_locations = []
    fastq_files = @study.study_files.by_type('Fastq').select {|f| !f.human_data}
    [fastq_files, @study.directory_listings.primary_data].flatten.each do |entry|
      @primary_data_locations << ["#{entry.name} (#{entry.description})", "#{entry.class.name.downcase}--#{entry.name}"]
    end
  end

  # check various firecloud statuses/permissions, but only if a study is not 'detached'
  def set_firecloud_permissions(study_detached)
    @allow_firecloud_access = false
    @allow_downloads = false
    @allow_edits = false
    @allow_computes = false
    return if study_detached
    begin
      @allow_firecloud_access = AdminConfiguration.firecloud_access_enabled?
      api_status = ApplicationController.firecloud_client.api_status
      # reuse status object because firecloud_client.services_available? each makes a separate status call
      # calling Hash#dig will gracefully handle any key lookup errors in case of a larger outage
      if api_status.is_a?(Hash)
        system_status = api_status['systems']
        sam_ok = system_status.dig(FireCloudClient::SAM_SERVICE, 'ok') == true # do equality check in case 'ok' node isn't present
        agora_ok = system_status.dig(FireCloudClient::AGORA_SERVICE, 'ok')
        rawls_ok = system_status.dig(FireCloudClient::RAWLS_SERVICE, 'ok') == true
        buckets_ok = system_status.dig(FireCloudClient::BUCKETS_SERVICE, 'ok') == true
        @allow_downloads = buckets_ok
        @allow_edits = sam_ok && rawls_ok
        @allow_computes = sam_ok && rawls_ok && agora_ok
      end
    rescue => e
      logger.error "Error checking FireCloud API status: #{e.class.name} -- #{e.message}"
      error_context = ErrorTracker.format_extra_context(@study, {firecloud_status: api_status})
      ErrorTracker.report_exception(e, current_user, error_context)
      MetricsService.report_error(e, request, current_user, @study)
    end
  end

  # set various study permissions based on the results of the above FC permissions
  def set_study_permissions(study_detached)
    @user_can_edit = false
    @user_can_compute = false
    @user_can_download = false
    @user_embargoed = false

    return if study_detached || !@allow_firecloud_access
    begin
      @user_can_edit = @study.can_edit?(current_user)
      if @allow_computes
        @user_can_compute = @study.can_compute?(current_user)
      end
      if @allow_downloads
        @user_can_download = @user_can_edit ? true : @study.can_download?(current_user)
        @user_embargoed = @user_can_edit ? false : @study.embargoed?(current_user)
      end
    rescue => e
      logger.error "Error setting study permissions: #{e.class.name} -- #{e.message}"
      error_context = ErrorTracker.format_extra_context(@study)
      ErrorTracker.report_exception(e, current_user, error_context)
      MetricsService.report_error(e, request, current_user, @study)
    end
  end

  # set all file download variables for study_download tab
  def set_study_download_options
    @study_files = @study.study_files.non_primary_data.sort_by(&:name)
    @primary_study_files = @study.study_files.primary_data
    @directories = @study.directory_listings.are_synced
    @primary_data = @study.directory_listings.primary_data
    @other_data = @study.directory_listings.non_primary_data

    # load download agreement/user acceptance, if present
    if @study.has_download_agreement?
      @download_agreement = @study.download_agreement
      @user_accepted_agreement = @download_agreement.user_accepted?(current_user)
    end
  end

  # whitelist parameters for updating studies on study settings tab (smaller list than in studies controller)
  def study_params
    params.require(:study).permit(:name, :description, :public, :embargo, :cell_count,
                                  :default_options => [:cluster, :annotation, :color_profile, :expression_label, :deliver_emails,
                                                       :cluster_point_size, :cluster_point_alpha, :cluster_point_border],
                                  study_shares_attributes: [:id, :_destroy, :email, :permission],
                                  study_detail_attributes: [:id, :full_description])
  end

  # whitelist parameters for creating custom user annotation
  def user_annotation_params
    params.require(:user_annotation).permit(:_id, :name, :study_id, :user_id, :cluster_group_id, :subsample_threshold,
                                            :loaded_annotation, :subsample_annotation, user_data_arrays_attributes: [:name, :values])
  end

  def download_acceptance_params
    params.require(:download_acceptance).permit(:email, :download_agreement_id)
  end

  # make sure user has view permissions for selected study
  def check_view_permissions
    unless @study.public?
      if (!user_signed_in? && !@study.public?)
        authenticate_user!
      elsif (user_signed_in? && !@study.can_view?(current_user))
        alert = 'You do not have permission to perform that action.'
        respond_to do |format|
          format.js {render js: "alert('#{alert}')" and return}
          format.html {redirect_to merge_default_redirect_params(site_path, scpbr: params[:scpbr]), alert: alert and return}
        end
      end
    end
  end

  # check compute permissions for study
  def check_compute_permissions
    if ApplicationController.firecloud_client.services_available?(FireCloudClient::SAM_SERVICE, FireCloudClient::RAWLS_SERVICE)
      if !user_signed_in? || !@study.can_compute?(current_user)
        @alert ='You do not have permission to perform that action.'
        respond_to do |format|
          format.js {render action: :notice}
          format.html {redirect_to merge_default_redirect_params(site_path, scpbr: params[:scpbr]), alert: @alert and return}
          format.json {head 403}
        end
      end
    else
      @alert ='Compute services are currently unavailable - please check back later.'
      respond_to do |format|
        format.js {render action: :notice}
        format.html {redirect_to merge_default_redirect_params(site_path, scpbr: params[:scpbr]), alert: @alert and return}
        format.json {head 503}
      end
    end
  end

  # check permissions manually on AJAX call via authentication token
  def check_xhr_view_permissions
    unless @study.public?
      if params[:request_user_token].nil?
        return false
      else
        request_user_id, auth_token = params[:request_user_token].split(':')
        request_user = User.find_by(id: request_user_id, authentication_token: auth_token)
        unless !request_user.nil? && @study.can_view?(request_user)
          return false
        end
      end
      return true
    else
      return true
    end
  end

  # check if a study is 'detached' from a workspace
  def check_study_detached
    if @study.detached?
      @alert = "We were unable to complete your request as #{@study.accession} is detached from the workspace (maybe the workspace was deleted?)"
      respond_to do |format|
        format.js {render js: "alert('#{@alert}');"}
        format.html {redirect_to merge_default_redirect_params(site_path, scpbr: params[:scpbr]), alert: @alert and return}
        format.json {render json: {error: @alert}, status: 410}
      end
    end
  end

  ###
  #
  # SEARCH SUB METHODS
  #
  ###

  # load expression matrix ids for optimized search speed
  def load_study_expression_matrix_ids(study_id)
    StudyFile.where(study_id: study_id, :file_type.in => ['Expression Matrix', 'MM Coordinate Matrix']).map(&:id)
  end

  # generic search term parser
  def parse_search_terms(key)
    terms = params[:search][key]
    sanitized_terms = sanitize_search_values(terms)
    if sanitized_terms.is_a?(Array)
      sanitized_terms.map(&:strip)
    else
      sanitized_terms.split(/[\n\s,]/).map(&:strip)
    end
  end

  # generic expression score getter, preserves order and discards empty matches
  def load_expression_scores(terms)
    genes = []
    matrix_ids = load_study_expression_matrix_ids(@study.id)
    terms.each do |term|
      matches = @study.genes.by_name_or_id(term, matrix_ids)
      unless matches.empty?
        genes << matches
      end
    end
    genes
  end

  # search genes and save terms not found.  does not actually load expression scores to improve search speed,
  # but rather just matches gene names if possible.  to load expression values, use load_expression_scores
  def search_expression_scores(terms, study_id)
    genes = []
    not_found = []
    file_ids = load_study_expression_matrix_ids(study_id)
    terms.each do |term|
      if Gene.study_has_gene?(study_id: study_id, expr_matrix_ids: file_ids, gene_name: term)
        genes << {'name' => term}
      else
        not_found << {'name' => term}
      end
    end
    [genes, not_found]
  end

  # load best-matching gene (if possible)
  def load_best_gene_match(matches, search_term)
    # iterate through all matches to see if there is an exact match
    matches.each do |match|
      if match['name'] == search_term
        return match
      end
    end
    # go through a second time to see if there is a case-insensitive match by looking at searchable_gene
    # this is done after a complete iteration to ensure that there wasn't an exact match available
    matches.each do |match|
      if match['searchable_name'] == search_term.downcase
        return match
      end
    end
  end

  # sanitize search values
  def sanitize_search_values(terms)
    RequestUtils.sanitize_search_terms(terms)
  end

  ###
  #
  # MISCELLANEOUS SUB METHODS
  #
  ###

  # defaults for annotation fonts
  def annotation_font
    {
        family: 'Helvetica Neue',
        size: 10,
        color: '#333'
    }
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
        x: coordinates_file.x_axis_label.blank? ? 'X' : coordinates_file.x_axis_label,
        y: coordinates_file.y_axis_label.blank? ? 'Y' : coordinates_file.y_axis_label,
        z: coordinates_file.z_axis_label.blank? ? 'Z' : coordinates_file.z_axis_label
    }
  end

  def load_expression_axis_title
    @study.default_expression_label
  end

  # create a unique hex digest of a list of genes for use in set_cache_path
  def construct_gene_list_hash(query_list)
    genes = query_list.split(' ').map(&:strip).sort.join
    Digest::SHA256.hexdigest genes
  end

  # update sample table with contents of sample map
  def populate_rows(existing_list, file_list)
    # create hash of samples => array of reads
    sample_map = DirectoryListing.sample_read_pairings(file_list)
    sample_map.each do |sample, files|
      row = [sample]
      row += files
      # pad out row to make sure it has the correct number of entries (5)
      0.upto(4) {|i| row[i] ||= '' }
      existing_list << row
    end
  end

  # load list of available workflows
  def load_available_workflows
    AnalysisConfiguration.available_analyses
  end

  # update AnalysisSubmissions when loading study analysis tab
  # will not backfill existing workflows to keep our submission history clean
  def update_analysis_submission(submission)
    analysis_submission = AnalysisSubmission.find_by(submission_id: submission['submissionId'])
    if analysis_submission.present?
      workflow_status = submission['workflowStatuses'].keys.first # this only works for single-workflow analyses
      analysis_submission.update(status: workflow_status)
      analysis_submission.delay.set_completed_on # run in background to avoid UI blocking
    end
  end

  protected

  # construct a path to store cache results based on query parameters
  def set_cache_path
    params_key = "_#{params[:cluster].to_s.split.join('-')}_#{params[:annotation]}"
    case action_name
    when 'render_gene_expression_plots'
      unless params[:subsample].blank?
        params_key += "_#{params[:subsample]}"
      end
      unless params[:boxpoints].blank?
        params_key += "_#{params[:boxpoints]}"
      end
      params_key += "_#{params[:plot_type]}"
      render_gene_expression_plots_url(accession: params[:accession], study_name: params[:study_name],
                                       gene: params[:gene]) + params_key
    when 'render_global_gene_expression_plots'
      unless params[:subsample].blank?
        params_key += "_#{params[:subsample]}"
      end
      unless params[:identifier].blank?
        params_key += "_#{params[:identifier]}"
      end
      params_key += "_#{params[:plot_type]}"
      render_global_gene_expression_plots_url(accession: params[:accession], study_name: params[:study_name],
                                              gene: params[:gene]) + params_key
    when 'render_gene_set_expression_plots'
      unless params[:subsample].blank?
        params_key += "_#{params[:subsample]}"
      end
      if params[:gene_set]
        params_key += "_#{params[:gene_set].split.join('-')}"
      else
        gene_list = params[:search][:genes]
        gene_key = construct_gene_list_hash(gene_list)
        params_key += "_#{gene_key}"
      end
      params_key += "_#{params[:plot_type]}"
      unless params[:consensus].blank?
        params_key += "_#{params[:consensus]}"
      end
      unless params[:boxpoints].blank?
        params_key += "_#{params[:boxpoints]}"
      end
      render_gene_set_expression_plots_url(accession: params[:accession], study_name: params[:study_name]) + params_key
    when 'expression_query'
      params_key += "_#{params[:row_centered]}"
      gene_list = params[:search][:genes]
      gene_key = construct_gene_list_hash(gene_list)
      params_key += "_#{gene_key}"
      expression_query_url(accession: params[:accession], study_name: params[:study_name]) + params_key
    when 'annotation_query'
      annotation_query_url(accession: params[:accession], study_name: params[:study_name]) + params_key
    when 'precomputed_results'
      precomputed_results_url(accession: params[:accession], study_name: params[:study_name],
                              precomputed: params[:precomputed].split.join('-'))
    end
  end
end
