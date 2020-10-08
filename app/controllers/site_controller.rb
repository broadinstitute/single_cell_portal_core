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
                                     :view_workflow_wdl, :create_totat, :log_action, :get_taxon, :get_taxon_assemblies, :covid19]
  before_action :set_cluster_group, only: [:study, :render_cluster, :render_gene_expression_plots, :render_global_gene_expression_plots,
                                           :render_gene_set_expression_plots, :view_gene_expression, :view_gene_set_expression,
                                           :view_gene_expression_heatmap, :view_precomputed_gene_expression_heatmap, :expression_query,
                                           :annotation_query, :get_new_annotations, :annotation_values, :show_user_annotations_form]
  before_action :set_selected_annotation, only: [:render_cluster, :render_gene_expression_plots, :render_global_gene_expression_plots,
                                                 :render_gene_set_expression_plots, :view_gene_expression, :view_gene_set_expression,
                                                 :view_gene_expression_heatmap, :view_precomputed_gene_expression_heatmap, :annotation_query,
                                                 :annotation_values, :show_user_annotations_form]
  before_action :load_precomputed_options, only: [:study, :update_study_settings, :render_cluster, :render_gene_expression_plots,
                                                  :render_gene_set_expression_plots, :view_gene_expression, :view_gene_set_expression,
                                                  :view_gene_expression_heatmap, :view_precomputed_gene_expression_heatmap]
  before_action :check_view_permissions, except: [:index, :legacy_study, :get_viewable_studies, :search_all_genes, :render_global_gene_expression_plots, :privacy_policy,
                                                  :terms_of_service, :search, :precomputed_results, :expression_query, :annotation_query, :view_workflow_wdl,
                                                  :log_action, :get_workspace_samples, :update_workspace_samples, :create_totat,
                                                  :get_workflow_options, :get_taxon, :get_taxon_assemblies, :covid19, :record_download_acceptance]
  before_action :check_compute_permissions, only: [:get_fastq_files, :get_workspace_samples, :update_workspace_samples,
                                                   :delete_workspace_samples, :get_workspace_submissions, :create_workspace_submission,
                                                   :get_submission_workflow, :abort_submission_workflow, :get_submission_errors,
                                                   :get_submission_outputs, :delete_submission_files, :get_submission_metadata]
  before_action :check_study_detached, only: [:download_file, :update_study_settings, :download_bulk_files,
                                              :get_fastq_files, :get_workspace_samples, :update_workspace_samples,
                                              :delete_workspace_samples, :get_workspace_submissions, :create_workspace_submission,
                                              :get_submission_workflow, :abort_submission_workflow, :get_submission_errors,
                                              :get_submission_outputs, :delete_submission_files, :get_submission_metadata]

  # caching
  caches_action :render_cluster, :render_gene_expression_plots, :render_gene_set_expression_plots, :render_global_gene_expression_plots,
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
                  alert: 'Study not found.  Please check the name and try again.' and return
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
          set_study_default_options
          if @study.initialized?
            @cluster = @study.default_cluster
            @options = load_cluster_group_options
            @cluster_annotations = load_cluster_group_annotations
            set_selected_annotation
          end

          @study_files = @study.study_files.non_primary_data.sort_by(&:name)
          @primary_study_files = @study.study_files.by_type('Fastq')
          @directories = @study.directory_listings.are_synced
          @primary_data = @study.directory_listings.primary_data
          @other_data = @study.directory_listings.non_primary_data

          # double check on download availability: first, check if administrator has disabled downloads
          # then check if FireCloud is available and disable download links if either is true
          @allow_downloads = ApplicationController.firecloud_client.services_available?(FireCloudClient::BUCKETS_SERVICE)
        else
          set_study_default_options
        end
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
    @study_files = @study.study_files.non_primary_data.sort_by(&:name)
    @primary_study_files = @study.study_files.primary_data
    @directories = @study.directory_listings.are_synced
    @primary_data = @study.directory_listings.primary_data
    @other_data = @study.directory_listings.non_primary_data
    @unique_genes = @study.unique_genes

    # double check on download availability: first, check if administrator has disabled downloads
    # then check individual statuses to see what to enable/disable
    # if the study is 'detached', then everything is set to false by default
    set_firecloud_permissions(@study.detached?)
    set_study_permissions(@study.detached?)
    set_study_default_options
    # load options and annotations
    if @study.can_visualize_clusters?
      @options = load_cluster_group_options
      @cluster_annotations = load_cluster_group_annotations
      # call set_selected_annotation manually
      set_selected_annotation
    end

    if @study.has_download_agreement?
      @download_agreement = @study.download_agreement
      @user_accepted_agreement = @download_agreement.user_accepted?(current_user)
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

  # render a single cluster and its constituent sub-clusters
  def render_cluster
    subsample = params[:subsample].blank? ? nil : params[:subsample].to_i
    @coordinates = load_cluster_group_data_array_points(@selected_annotation, subsample)
    @plot_type = @cluster.is_3d? ? 'scatter3d' : 'scattergl'
    @options = load_cluster_group_options
    @cluster_annotations = load_cluster_group_annotations
    if @cluster.has_coordinate_labels?
      @coordinate_labels = load_cluster_group_coordinate_labels
    end

    if @cluster.is_3d?
      @range = set_range(@coordinates.values)
      if @cluster.has_range?
        @aspect = compute_aspect_ratios(@range)
      end
    end
    @axes = load_axis_labels

    cluster_name = @cluster.name
    annot_name = params[:annotation]

    # load data for visualization, if present
    @analysis_outputs = {}
    if @selected_annotation[:type] == 'group' && @study.has_analysis_outputs?('infercnv', 'ideogram.js', cluster_name, annot_name)
      ideogram_annotations = @study.get_analysis_outputs('infercnv', 'ideogram.js', cluster_name, annot_name).first
      @analysis_outputs['ideogram.js'] = ideogram_annotations.api_url
    end

    # load default color profile if necessary
    if params[:annotation] == @study.default_annotation && @study.default_annotation_type == 'numeric' && !@study.default_color_profile.nil?
      @coordinates[:all][:marker][:colorscale] = @study.default_color_profile
    end

    respond_to do |format|
      format.js
    end
  end

  ## GENE-BASED

  # render box and scatter plots for parent clusters or a particular sub cluster
  def view_gene_expression
    @options = load_cluster_group_options
    @cluster_annotations = load_cluster_group_annotations
    @top_plot_partial = @selected_annotation[:type] == 'group' ? 'expression_plots_view' : 'expression_annotation_plots_view'
    @y_axis_title = load_expression_axis_title

    @taxons = @study.infer_taxons(params[:gene])

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
    @y_axis_title = load_expression_axis_title
    # depending on annotation type selection, set up necessary partial names to use in rendering
    if @selected_annotation[:type] == 'group'
      @values = load_expression_boxplot_data_array_scores(@selected_annotation, subsample)
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
      @values = load_annotation_based_data_array_scatter(@selected_annotation, subsample)
      @top_plot_partial = 'expression_annotation_plots_view'
      @top_plot_plotly = 'expression_annotation_plots_plotly'
      @top_plot_layout = 'expression_annotation_scatter_layout'
      @annotation_scatter_range = set_range(@values.values)
    end
    @expression = load_expression_data_array_points(@selected_annotation, subsample)
    @options = load_cluster_group_options
    @range = set_range([@expression[:all]])
    @coordinates = load_cluster_group_data_array_points(@selected_annotation, subsample)
    if @cluster.has_coordinate_labels?
      @coordinate_labels = load_cluster_group_coordinate_labels
    end
    @static_range = set_range(@coordinates.values)
    if @cluster.is_3d? && @cluster.has_range?
      @expression_aspect = compute_aspect_ratios(@range)
      @static_aspect = compute_aspect_ratios(@static_range)
    end
    @cluster_annotations = load_cluster_group_annotations

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
      @y_axis_title = load_expression_axis_title
      if @selected_annotation[:type] == 'group'
        @values = load_expression_boxplot_data_array_scores(@selected_annotation, subsample)
        @values_jitter = params[:boxpoints]
      else
        @values = load_annotation_based_data_array_scatter(@selected_annotation, subsample)
      end
      @options = load_cluster_group_options
      @cluster_annotations = load_cluster_group_annotations
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
    @y_axis_title = consensus + ' ' + load_expression_axis_title
    # depending on annotation type selection, set up necessary partial names to use in rendering
    @options = load_cluster_group_options
    @cluster_annotations = load_cluster_group_annotations
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
    @y_axis_title = consensus + ' ' + load_expression_axis_title
    # depending on annotation type selection, set up necessary partial names to use in rendering
    if @selected_annotation[:type] == 'group'
      @values = load_gene_set_expression_boxplot_scores(@selected_annotation, params[:consensus], subsample)
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
      @values = load_gene_set_annotation_based_scatter(@selected_annotation, params[:consensus], subsample)
      @top_plot_partial = 'expression_annotation_plots_view'
      @top_plot_plotly = 'expression_annotation_plots_plotly'
      @top_plot_layout = 'expression_annotation_scatter_layout'
      @annotation_scatter_range = set_range(@values.values)
    end
    # load expression scatter using main gene expression values
    @expression = load_gene_set_expression_data_arrays(@selected_annotation, params[:consensus], subsample)
    @expression[:all][:marker][:cmin], @expression[:all][:marker][:cmax] = RequestUtils.get_minmax(@expression[:all][:marker][:color])

    # load static cluster reference plot
    @coordinates = load_cluster_group_data_array_points(@selected_annotation, subsample)
    # set up options, annotations and ranges
    @options = load_cluster_group_options
    @range = set_range([@expression[:all]])
    @static_range = set_range(@coordinates.values)

    if @cluster.is_3d? && @cluster.has_range?
      @expression_aspect = compute_aspect_ratios(@range)
      @static_aspect = compute_aspect_ratios(@static_range)
    end

    @cluster_annotations = load_cluster_group_annotations

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
    @options = load_cluster_group_options
    @cluster_annotations = load_cluster_group_annotations
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
    @cluster_annotations = load_cluster_group_annotations
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
    @options = load_cluster_group_options
    @cluster_annotations = load_cluster_group_annotations
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

  def create_totat
    if !user_signed_in?
      error = {'message': "Forbidden: You must be signed in to do this"}
      render json:  + error, status: 403
    end
    half_hour = 1800 # seconds
    totat_and_ti = current_user.create_totat(time_interval=half_hour)
    render json: totat_and_ti
  end

  # Returns text file listing signed URLs, etc. of files for download via curl.
  # That is, this return 'cfg.txt' used as config (K) argument in 'curl -K cfg.txt'
  def download_bulk_files

    # Ensure study is public
    if !@study.public?
      message = 'Only public studies can be downloaded via curl.'
      render plain: "Forbidden: " + message, status: 403
      return
    end

    if @study.has_download_agreement? && !@study.download_agreement.user_accepted?(current_user)
      render plain: "Forbidden: Download agreement not accepted for #{@study.accession}" , status: 403
      return
    end

    # 'all' or the name of a directory, e.g. 'csvs'
    download_object = params[:download_object]

    totat = params[:totat]

    # Time-based one-time access token (totat) is used to track user's download quota
    valid_totat = User.verify_totat(totat)

    if valid_totat == false
      render plain: "Forbidden: Invalid access token " + totat, status: 403
      return
    else
      user = valid_totat
    end

    user_quota = user.daily_download_quota

    # Only check quota at beginning of download, not per file.
    # Studies might be massive, and we want user to be able to download at least
    # one requested download object per day.
    if user_quota >= @download_quota
      message = 'You have exceeded your current daily download quota.  You must wait until tomorrow to download this object.'
      render plain: "Forbidden: " + message, status: 403
      return
    end

    curl_configs = ['--create-dirs', '--compressed']

    curl_files = []

    # Gather all study files, if we're downloading whole study ('all')
    if download_object == 'all'
      files = @study.study_files.valid
      files.each do |study_file|
        unless study_file.human_data?
          curl_files.push(study_file)
        end
      end
    end

    # Gather all files in requested directory listings
    synced_dirs = @study.directory_listings.are_synced
    synced_dirs.each do |synced_dir|
      if download_object != 'all' and synced_dir[:name] != download_object
        next
      end
      synced_dir.files.each do |file|
        curl_files.push(file)
      end
    end

    start_time = Time.zone.now

    # Get signed URLs for all files in the requested download objects, and update user quota
    Parallel.map(curl_files, in_threads: 100) do |file|
      fc_client = FireCloudClient.new
      curl_config, file_size = get_curl_config(file, fc_client)
      curl_configs.push(curl_config)
      user_quota += file_size
    end

    end_time = Time.zone.now
    time = (end_time - start_time).divmod 60.0
    @log_message = ["#{@study.url_safe_name} curl configs generated!"]
    @log_message << "Signed URLs generated: #{curl_configs.size}"
    @log_message << "Total time in get_curl_config: #{time.first} minutes, #{time.last} seconds"
    logger.info @log_message.join("\n")

    curl_configs = curl_configs.join("\n\n")

    user.update(daily_download_quota: user_quota)

    send_data curl_configs, type: 'text/plain', filename: 'cfg.txt'
  end

  ###
  #
  # ANNOTATION METHODS
  #
  ###

  # render the 'Create Annotations' form (must be done via ajax to get around page caching issues)
  def show_user_annotations_form

  end

  # Method to create user annotations from box or lasso selection
  def create_user_annotations

    # Data name is an array of the values of labels
    @data_names = []

    #Error handling block to create annotation
    begin
      # Get the label values and push to data names
      user_annotation_params[:user_data_arrays_attributes].keys.each do |key|
        user_annotation_params[:user_data_arrays_attributes][key][:values] =  user_annotation_params[:user_data_arrays_attributes][key][:values].split(',')
        @data_names.push(user_annotation_params[:user_data_arrays_attributes][key][:name].strip )
      end

      # Create the annotation
      @user_annotation = UserAnnotation.new(user_id: user_annotation_params[:user_id], study_id: user_annotation_params[:study_id],
                                            cluster_group_id: user_annotation_params[:cluster_group_id],
                                            values: @data_names, name: user_annotation_params[:name],
                                            source_resolution: user_annotation_params[:subsample_threshold].present? ? user_annotation_params[:subsample_threshold].to_i : nil)

      # override cluster setter to use the current selected cluster, needed for reloading
      @cluster = @user_annotation.cluster_group

      # Error handling, save the annotation and handle exceptions
      if @user_annotation.save
        # Method call to create the user data arrays for this annotation
        @user_annotation.initialize_user_data_arrays(user_annotation_params[:user_data_arrays_attributes], user_annotation_params[:subsample_annotation],user_annotation_params[:subsample_threshold], user_annotation_params[:loaded_annotation])

        # Reset the annotations in the dropdowns to include this new annotation
        @cluster_annotations = load_cluster_group_annotations
        @options = load_cluster_group_options

        # No need for an alert, only a message saying successfully created
        @alert = nil
        @notice = "User Annotation: '#{@user_annotation.name}' successfully saved. You may now view this annotation via the annotations dropdown."

        # Update the dropdown partial
        render 'update_user_annotations'
      else
        # If there was an error saving, reload and alert the use something broke
        @cluster_annotations = load_cluster_group_annotations
        @options = load_cluster_group_options
        @notice = nil
        @alert = 'The following errors prevented the annotation from being saved: ' + @user_annotation.errors.full_messages.join(',')
        logger.error "Creating user annotation of params: #{user_annotation_params}, unable to save user annotation with errors #{@user_annotation.errors.full_messages.join(', ')}"
        render 'update_user_annotations'
      end
        # More error handling, this is if can't save user annotation
    rescue Mongoid::Errors::InvalidValue => e
      sanitized_params = user_annotation_params.dup
      sanitized_params.delete(:user_data_arrays_attributes) # remove data_arrays attributes due to size
      error_context = ErrorTracker.format_extra_context(@study, {params: sanitized_params})
      ErrorTracker.report_exception(e, current_user, error_context)
      # If an invalid value was somehow passed through the form, and couldn't save the annotation
      @cluster_annotations = load_cluster_group_annotations
      @options = load_cluster_group_options
      @notice = nil
      @alert = 'The following errors prevented the annotation from being saved: ' + 'Invalid data type submitted. (' + e.problem + '. ' + e.resolution + ')'
      logger.error "Creating user annotation of params: #{user_annotation_params}, invalid value of #{e.message}"
      render 'update_user_annotations'

    rescue NoMethodError => e
      sanitized_params = user_annotation_params.dup
      sanitized_params.delete(:user_data_arrays_attributes) # remove data_arrays attributes due to size
      error_context = ErrorTracker.format_extra_context(@study, {params: sanitized_params})
      ErrorTracker.report_exception(e, current_user, error_context)
      # If something is nil and can't have a method called on it, respond with an alert
      @cluster_annotations = load_cluster_group_annotations
      @options = load_cluster_group_options
      @notice = nil
      @alert = 'The following errors prevented the annotation from being saved: ' + e.message
      logger.error "Creating user annotation of params: #{user_annotation_params}, no method error #{e.message}"
      render 'update_user_annotations'

    rescue => e
      sanitized_params = user_annotation_params.dup
      sanitized_params.delete(:user_data_arrays_attributes) # remove data_arrays attributes due to size
      error_context = ErrorTracker.format_extra_context(@study, {params: sanitized_params})
      ErrorTracker.report_exception(e, current_user, error_context)
      # If a generic unexpected error occurred and couldn't save the annotation
      @cluster_annotations = load_cluster_group_annotations
      @options = load_cluster_group_options
      @notice = nil
      @alert = 'An unexpected error prevented the annotation from being saved: ' + e.message
      logger.error "Creating user annotation of params: #{user_annotation_params}, unexpected error #{e.message}"
      render 'update_user_annotations'
    end
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
      redirect_to merge_default_redirect_params(site_path, scpbr: params[:scpbr]), alert: 'Study not found.  Please check the name and try again.' and return
    end
        #Check if current url_safe_name matches model
    unless @study.url_safe_name == params[:study_name]
           redirect_to merge_default_redirect_params(view_study_path(accession: params[:accession],
                                                                     study_name: @study.url_safe_name,
                                                                     scpbr:params[:scpbr])) and return
      end

  end

  def set_cluster_group
    @cluster = RequestUtils.get_cluster_group(params, @study)
  end

  def set_selected_annotation
    @selected_annotation = RequestUtils.get_selected_annotation(params, @study, @cluster)
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
      @alert = 'We were unable to complete your request as the study is question is detached from the workspace (maybe the workspace was deleted?)'
      respond_to do |format|
        format.js {render js: "alert('#{@alert}');"}
        format.html {redirect_to merge_default_redirect_params(site_path, scpbr: params[:scpbr]), alert: @alert and return}
        format.json {render json: {error: @alert}, status: 410}
      end
    end
  end

  ###
  #
  # DATA FORMATTING SUB METHODS
  #
  ###

  # generic method to populate data structure to render a cluster scatter plot
  # uses cluster_group model and loads annotation for both group & numeric plots
  # data values are pulled from associated data_array entries for each axis and annotation/text value
  def load_cluster_group_data_array_points(annotation, subsample_threshold=nil)
    # construct annotation key to load subsample data_arrays if needed, will be identical to params[:annotation]
    subsample_annotation = "#{annotation[:name]}--#{annotation[:type]}--#{annotation[:scope]}"
    x_array = @cluster.concatenate_data_arrays('x', 'coordinates', subsample_threshold, subsample_annotation)
    y_array = @cluster.concatenate_data_arrays('y', 'coordinates', subsample_threshold, subsample_annotation)
    z_array = @cluster.concatenate_data_arrays('z', 'coordinates', subsample_threshold, subsample_annotation)
    cells = @cluster.concatenate_data_arrays('text', 'cells', subsample_threshold, subsample_annotation)
    annotation_array = []
    annotation_hash = {}
    # Construct the arrays based on scope
    if annotation[:scope] == 'cluster'
      annotation_array = @cluster.concatenate_data_arrays(annotation[:name], 'annotations', subsample_threshold, subsample_annotation)
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
      metadata_obj = @study.cell_metadata.by_name_and_type(annotation[:name], annotation[:type])
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
              size: @study.default_cluster_point_size,
              line: { color: 'rgb(40,40,40)', width: @study.show_cluster_point_borders? ? 0.5 : 0},
              colorscale: params[:colorscale].blank? ? 'Reds' : params[:colorscale],
              showscale: true,
              colorbar: {
                  title: annotation[:name] ,
                  titleside: 'right'
              }
          }
      }
      if @cluster.is_3d?
        coordinates[:all][:z] = z_array
      end
    else
      # assemble containers for each trace
      annotation[:values].each do |value|
        coordinates[value] = {x: [], y: [], text: [], cells: [], annotations: [], name: value,
                              marker: {size: @study.default_cluster_point_size, line: { color: 'rgb(40,40,40)', width: @study.show_cluster_point_borders? ? 0.5 : 0}}}
        if @cluster.is_3d?
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
          if @cluster.is_3d?
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
            if @cluster.is_3d?
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

  # method to load a 2-d scatter of selected numeric annotation vs. gene expression
  def load_annotation_based_data_array_scatter(annotation, subsample_threshold=nil)
    # construct annotation key to load subsample data_arrays if needed, will be identical to params[:annotation]
    subsample_annotation = "#{annotation[:name]}--#{annotation[:type]}--#{annotation[:scope]}"
    cells = @cluster.concatenate_data_arrays('text', 'cells', subsample_threshold, subsample_annotation)
    annotation_array = []
    annotation_hash = {}
    if annotation[:scope] == 'cluster'
      annotation_array = @cluster.concatenate_data_arrays(annotation[:name], 'annotations', subsample_threshold, subsample_annotation)
    elsif annotation[:scope] == 'user'
      # for user annotations, we have to load by id as names may not be unique to clusters
      user_annotation = UserAnnotation.find(annotation[:id])
      subsample_annotation = user_annotation.formatted_annotation_identifier
      annotation_array = user_annotation.concatenate_user_data_arrays(annotation[:name], 'annotations', subsample_threshold, subsample_annotation)
      cells = user_annotation.concatenate_user_data_arrays('text', 'cells', subsample_threshold, subsample_annotation)
    else
      # for study-wide annotations, load from study_metadata values instead of cluster-specific annotations
      metadata_obj = @study.cell_metadata.by_name_and_type(annotation[:name], annotation[:type])
      annotation_hash = metadata_obj.cell_annotations
    end
    values = {}
    values[:all] = {x: [], y: [], cells: [], annotations: [], text: [], marker: {size: @study.default_cluster_point_size,
                                                                                 line: { color: 'rgb(40,40,40)', width: @study.show_cluster_point_borders? ? 0.5 : 0}}}
    if annotation[:scope] == 'cluster' || annotation[:scope] == 'user'
      annotation_array.each_with_index do |annot, index|
        annotation_value = annot
        cell_name = cells[index]
        expression_value = @gene['scores'][cell_name].to_f.round(4)

        values[:all][:text] << "<b>#{cell_name}</b><br>#{annotation_value}<br>#{@y_axis_title}: #{expression_value}"
        values[:all][:annotations] << annotation_value
        values[:all][:x] << annotation_value
        values[:all][:y] << expression_value
        values[:all][:cells] << cell_name
      end
    else
      cells.each do |cell|
        if annotation_hash.has_key?(cell)
          annotation_value = annotation_hash[cell]
          expression_value = @gene['scores'][cell].to_f.round(4)
          values[:all][:text] << "<b>#{cell}</b><br>#{annotation_value}<br>#{@y_axis_title}: #{expression_value}"
          values[:all][:annotations] << annotation_value
          values[:all][:x] << annotation_value
          values[:all][:y] << expression_value
          values[:all][:cells] << cell
        end
      end
    end
    values
  end

  # method to load a 2-d scatter of selected numeric annotation vs. gene set expression
  # will support a variety of consensus modes (default is mean)
  def load_gene_set_annotation_based_scatter(annotation, consensus, subsample_threshold=nil)
    # construct annotation key to load subsample data_arrays if needed, will be identical to params[:annotation]
    subsample_annotation = "#{annotation[:name]}--#{annotation[:type]}--#{annotation[:scope]}"
    values = {}
    values[:all] = {x: [], y: [], cells: [], annotations: [], text: [], marker: {size: @study.default_cluster_point_size,
                                                                                 line: { color: 'rgb(40,40,40)', width: @study.show_cluster_point_borders? ? 0.5 : 0}}}
    cells = @cluster.concatenate_data_arrays('text', 'cells', subsample_threshold, subsample_annotation)
    annotation_array = []
    annotation_hash = {}
    if annotation[:scope] == 'cluster'
      annotation_array = @cluster.concatenate_data_arrays(annotation[:name], 'annotations', subsample_threshold, subsample_annotation)
    elsif annotation[:scope] == 'user'
      # for user annotations, we have to load by id as names may not be unique to clusters
      user_annotation = UserAnnotation.find(annotation[:id])
      subsample_annotation = user_annotation.formatted_annotation_identifier
      annotation_array = user_annotation.concatenate_user_data_arrays(annotation[:name], 'annotations', subsample_threshold, subsample_annotation)
      cells = user_annotation.concatenate_user_data_arrays('text', 'cells', subsample_threshold, subsample_annotation)
    else
      metadata_obj = @study.cell_metadata.by_name_and_type(annotation[:name], annotation[:type])
      annotation_hash = metadata_obj.cell_annotations
    end
    cells.each_with_index do |cell, index|
      annotation_value = annotation[:scope] == 'cluster' ? annotation_array[index] : annotation_hash[cell]
      if !annotation_value.nil?
        case consensus
          when 'mean'
            expression_value = calculate_mean(@genes, cell)
          when 'median'
            expression_value = calculate_median(@genes, cell)
          else
            expression_value = calculate_mean(@genes, cell)
        end
        values[:all][:text] << "<b>#{cell}</b><br>#{annotation_value}<br>#{@y_axis_title}: #{expression_value}"
        values[:all][:annotations] << annotation_value
        values[:all][:x] << annotation_value
        values[:all][:y] << expression_value
        values[:all][:cells] << cell
        end
    end
    values
  end

  # load box plot scores from gene expression values using data array of cell names for given cluster
  def load_expression_boxplot_data_array_scores(annotation, subsample_threshold=nil)
    # construct annotation key to load subsample data_arrays if needed, will be identical to params[:annotation]
    subsample_annotation = "#{annotation[:name]}--#{annotation[:type]}--#{annotation[:scope]}"
    values = initialize_plotly_objects_by_annotation(annotation)

    # grab all cells present in the cluster, and use as keys to load expression scores
    # if a cell is not present for the gene, score gets set as 0.0
    cells = @cluster.concatenate_data_arrays('text', 'cells', subsample_threshold, subsample_annotation)
    if annotation[:scope] == 'cluster'
      # we can take a subsample of the same size for the annotations since the sort order is non-stochastic (i.e. the indices chosen are the same every time for all arrays)
      annotations = @cluster.concatenate_data_arrays(annotation[:name], 'annotations', subsample_threshold, subsample_annotation)
      cells.each_with_index do |cell, index|
        values[annotations[index]][:y] << @gene['scores'][cell].to_f.round(4)
      end
    elsif annotation[:scope] == 'user'
      # for user annotations, we have to load by id as names may not be unique to clusters
      user_annotation = UserAnnotation.find(annotation[:id])
      subsample_annotation = user_annotation.formatted_annotation_identifier
      annotations = user_annotation.concatenate_user_data_arrays(annotation[:name], 'annotations', subsample_threshold, subsample_annotation)
      cells = user_annotation.concatenate_user_data_arrays('text', 'cells', subsample_threshold, subsample_annotation)
      cells.each_with_index do |cell, index|
        values[annotations[index]][:y] << @gene['scores'][cell].to_f.round(4)
      end
    else
      # since annotations are in a hash format, subsampling isn't necessary as we're going to retrieve values by key lookup
      annotations =  @study.cell_metadata.by_name_and_type(annotation[:name], annotation[:type]).cell_annotations
      cells.each do |cell|
        val = annotations[cell]
        # must check if key exists
        if values.has_key?(val)
          values[annotations[cell]][:y] << @gene['scores'][cell].to_f.round(4)
          values[annotations[cell]][:cells] << cell
        end
      end
    end
    # remove any empty values as annotations may have created keys that don't exist in cluster
    values.delete_if {|key, data| data[:y].empty?}
    values
  end

  # load cluster_group data_array values, but use expression scores to set numerical color array
  def load_expression_data_array_points(annotation, subsample_threshold=nil)
    # construct annotation key to load subsample data_arrays if needed, will be identical to params[:annotation]
    subsample_annotation = "#{annotation[:name]}--#{annotation[:type]}--#{annotation[:scope]}"
    x_array = @cluster.concatenate_data_arrays('x', 'coordinates', subsample_threshold, subsample_annotation)
    y_array = @cluster.concatenate_data_arrays('y', 'coordinates', subsample_threshold, subsample_annotation)
    z_array = @cluster.concatenate_data_arrays('z', 'coordinates', subsample_threshold, subsample_annotation)
    cells = @cluster.concatenate_data_arrays('text', 'cells', subsample_threshold, subsample_annotation)
    annotation_array = []
    annotation_hash = {}
    if annotation[:scope] == 'cluster'
      annotation_array = @cluster.concatenate_data_arrays(annotation[:name], 'annotations', subsample_threshold, subsample_annotation)
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
      # for study-wide annotations, load from cell_metadata values instead of cluster-specific annotations
      metadata_obj = @study.cell_metadata.by_name_and_type(annotation[:name], annotation[:type])
      annotation_hash = metadata_obj.cell_annotations
    end
    expression = {}
    expression[:all] = {
        x: x_array,
        y: y_array,
        annotations: [],
        text: [],
        cells: cells,
        marker: {cmax: 0, cmin: 0, color: [], size: @study.default_cluster_point_size, showscale: true, colorbar: {title: @y_axis_title , titleside: 'right'}}
    }
    if @cluster.is_3d?
      expression[:all][:z] = z_array
    end
    cells.each_with_index do |cell, index|
      expression_score = @gene['scores'][cell].to_f.round(4)
      # load correct annotation value based on scope
      annotation_value = annotation[:scope] == 'cluster' ? annotation_array[index] : annotation_hash[cell]
      text_value = "#{cell} (#{annotation_value})<br />#{@y_axis_title}: #{expression_score}"
      expression[:all][:annotations] << annotation_value
      expression[:all][:text] << text_value
      expression[:all][:marker][:color] << expression_score
    end
    expression[:all][:marker][:line] = { color: 'rgb(255,255,255)', width: @study.show_cluster_point_borders? ? 0.5 : 0}
    expression[:all][:marker][:cmin], expression[:all][:marker][:cmax] = RequestUtils.get_minmax(expression[:all][:marker][:color])
    expression[:all][:marker][:colorscale] = params[:colorscale].blank? ? 'Reds' : params[:colorscale]
    expression
  end

  # load boxplot expression scores vs. scores across each gene for all cells
  # will support a variety of consensus modes (default is mean)
  def load_gene_set_expression_boxplot_scores(annotation, consensus, subsample_threshold=nil)
    values = initialize_plotly_objects_by_annotation(annotation)
    # construct annotation key to load subsample data_arrays if needed, will be identical to params[:annotation]
    subsample_annotation = "#{annotation[:name]}--#{annotation[:type]}--#{annotation[:scope]}"
    # grab all cells present in the cluster, and use as keys to load expression scores
    # if a cell is not present for the gene, score gets set as 0.0
    # will check if there are more than SUBSAMPLE_THRESHOLD cells present in the cluster, and subsample accordingly
    # values hash will be assembled differently depending on annotation scope (cluster-based is array, study-based is a hash)
    cells = @cluster.concatenate_data_arrays('text', 'cells', subsample_threshold, subsample_annotation)
    if annotation[:scope] == 'cluster'
      annotations = @cluster.concatenate_data_arrays(annotation[:name], 'annotations', subsample_threshold, subsample_annotation)
      cells.each_with_index do |cell, index|
        values[annotations[index]][:annotations] << annotations[index]
        case consensus
          when 'mean'
            values[annotations[index]][:y] << calculate_mean(@genes, cell)
          when 'median'
            values[annotations[index]][:y] << calculate_median(@genes, cell)
          else
            values[annotations[index]][:y] << calculate_mean(@genes, cell)
        end
      end
    elsif annotation[:scope] == 'user'
      # for user annotations, we have to load by id as names may not be unique to clusters
      user_annotation = UserAnnotation.find(annotation[:id])
      subsample_annotation = user_annotation.formatted_annotation_identifier
      annotations = user_annotation.concatenate_user_data_arrays(annotation[:name], 'annotations', subsample_threshold, subsample_annotation)
      cells = user_annotation.concatenate_user_data_arrays('text', 'cells', subsample_threshold, subsample_annotation)
      cells.each_with_index do |cell, index|
        values[annotations[index]][:annotations] << annotations[index]
        case consensus
          when 'mean'
            values[annotations[index]][:y] << calculate_mean(@genes, cell)
          when 'median'
            values[annotations[index]][:y] << calculate_median(@genes, cell)
          else
            values[annotations[index]][:y] << calculate_mean(@genes, cell)
        end
      end
    else
      # no need to subsample annotation since they are in hash format (lookup done by key)
      annotations =  @study.cell_metadata.by_name_and_type(annotation[:name], annotation[:type]).cell_annotations
      cells.each do |cell|
        val = annotations[cell]
        # must check if key exists
        if values.has_key?(val)
          values[annotations[cell]][:cells] << cell
          case consensus
            when 'mean'
              values[annotations[cell]][:y] << calculate_mean(@genes, cell)
            when 'median'
              values[annotations[cell]][:y] << calculate_median(@genes, cell)
            else
              values[annotations[cell]][:y] << calculate_mean(@genes, cell)
          end
        end
      end
    end
    # remove any empty values as annotations may have created keys that don't exist in cluster
    values.delete_if {|key, data| data[:y].empty?}
    values
  end

  # load scatter expression scores with average of scores across each gene for all cells
  # uses data_array as source for each axis
  # will support a variety of consensus modes (default is mean)
  def load_gene_set_expression_data_arrays(annotation, consensus, subsample_threshold=nil)
    # construct annotation key to load subsample data_arrays if needed, will be identical to params[:annotation]
    subsample_annotation = "#{annotation[:name]}--#{annotation[:type]}--#{annotation[:scope]}"

    x_array = @cluster.concatenate_data_arrays('x', 'coordinates', subsample_threshold, subsample_annotation)
    y_array = @cluster.concatenate_data_arrays('y', 'coordinates', subsample_threshold, subsample_annotation)
    z_array = @cluster.concatenate_data_arrays('z', 'coordinates', subsample_threshold, subsample_annotation)
    cells = @cluster.concatenate_data_arrays('text', 'cells', subsample_threshold, subsample_annotation)
    annotation_array = []
    annotation_hash = {}
    if annotation[:scope] == 'cluster'
      annotation_array = @cluster.concatenate_data_arrays(annotation[:name], 'annotations', subsample_threshold, subsample_annotation)
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
      # for study-wide annotations, load from cell_metadata values instead of cluster-specific annotations
      metadata_obj = @study.cell_metadata.by_name_and_type(annotation[:name], annotation[:type])
      annotation_hash = metadata_obj.cell_annotations
    end
    expression = {}
    expression[:all] = {
        x: x_array,
        y: y_array,
        text: [],
        annotations: [],
        cells: cells,
        marker: {cmax: 0, cmin: 0, color: [], size: @study.default_cluster_point_size, showscale: true, colorbar: {title: @y_axis_title , titleside: 'right'}}
    }
    if @cluster.is_3d?
      expression[:all][:z] = z_array
    end
    cells.each_with_index do |cell, index|
      case consensus
        when 'mean'
          expression_score = calculate_mean(@genes, cell)
        when 'median'
          expression_score = calculate_median(@genes, cell)
        else
          expression_score = calculate_mean(@genes, cell)
      end

      # load correct annotation value based on scope
      annotation_value = annotation[:scope] == 'cluster' ? annotation_array[index] : annotation_hash[cell]
      text_value = "#{cell} (#{annotation_value})<br />#{@y_axis_title}: #{expression_score}"
      expression[:all][:annotations] << annotation_value
      expression[:all][:text] << text_value
      expression[:all][:marker][:color] << expression_score

    end
    expression[:all][:marker][:line] = { color: 'rgb(40,40,40)', width: @study.show_cluster_point_borders? ? 0.5 : 0}
    expression[:all][:marker][:cmin], expression[:all][:marker][:cmax] = RequestUtils.get_minmax(expression[:all][:marker][:color])
    expression[:all][:marker][:colorscale] = params[:colorscale].blank? ? 'Reds' : params[:colorscale]
    expression
  end

  # method to initialize containers for plotly by annotation values
  def initialize_plotly_objects_by_annotation(annotation)
    values = {}
    annotation[:values].each do |value|
      values["#{value}"] = {y: [], cells: [], annotations: [], name: "#{value}" }
    end
    values
  end

  # load custom coordinate-based annotation labels for a given cluster
  def load_cluster_group_coordinate_labels
    # assemble source data
    x_array = @cluster.concatenate_data_arrays('x', 'labels')
    y_array = @cluster.concatenate_data_arrays('y', 'labels')
    z_array = @cluster.concatenate_data_arrays('z', 'labels')
    text_array = @cluster.concatenate_data_arrays('text', 'labels')
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
              family: @cluster.coordinate_labels_options[:font_family],
              size: @cluster.coordinate_labels_options[:font_size],
              color: @cluster.coordinate_labels_options[:font_color]
          }
      }
    end
    annotations
  end

  # find mean of expression scores for a given cell & list of genes
  def calculate_mean(genes, cell)
    values = genes.map {|gene| gene['scores'][cell].to_f}
    values.mean
  end

  # find median expression score for a given cell & list of genes
  def calculate_median(genes, cell)
    values = genes.map {|gene| gene['scores'][cell].to_f}
    Gene.array_median(values)
  end

  # set the range for a plotly scatter, will default to data-defined if cluster hasn't defined its own ranges
  # dynamically determines range based on inputs & available axes
  def set_range(inputs)
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

  # compute the aspect ratio between all ranges and use to enforce equal-aspect ranges on 3d plots
  def compute_aspect_ratios(range)
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

  # helper method to load all possible cluster groups for a study
  def load_cluster_group_options
    @study.cluster_groups.map(&:name)
  end

  # helper method to load all available cluster_group-specific annotations
  def load_cluster_group_annotations
    grouped_options = @study.formatted_annotation_select(cluster: @cluster)
    # load available user annotations (if any)
    if user_signed_in?
      user_annotations = UserAnnotation.viewable_by_cluster(current_user, @cluster)
      unless user_annotations.empty?
        grouped_options['User Annotations'] = user_annotations.map {|annot| ["#{annot.name}", "#{annot.id}--group--user"] }
      end
    end
    grouped_options
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

  # Helper method for download_bulk_files.  Returns file's curl config, size.
  def get_curl_config(file, fc_client=nil)

    # Is this a study file, or a file from a directory listing?
    is_study_file = file.is_a? StudyFile

    if fc_client == nil
      fc_client = ApplicationController.firecloud_client
    end

    filename = (is_study_file ? file.upload_file_name : file[:name])

    begin
      signed_url = fc_client.execute_gcloud_method(:generate_signed_url, 0, @study.bucket_id, filename,
                                                   expires: 1.day.to_i) # 1 day in seconds, 86400
      curl_config = [
          'url="' + signed_url + '"',
          'output="' + filename + '"'
      ]
    rescue => e
      error_context = ErrorTracker.format_extra_context(@study)
      ErrorTracker.report_exception(e, current_user, error_context)
      logger.error "Error generating signed url for #{filename}; #{e.message}"
      curl_config = [
          '# Error downloading ' + filename + '.  ' +
          'Did you delete the file in the bucket and not sync it in Single Cell Portal?'
      ]
    end

    curl_config = curl_config.join("\n")
    file_size = (is_study_file ? file.upload_file_size : file[:size])

    return curl_config, file_size
  end

  protected

  # construct a path to store cache results based on query parameters
  def set_cache_path
    params_key = "_#{params[:cluster].to_s.split.join('-')}_#{params[:annotation]}"
    case action_name
    when 'render_cluster'
      unless params[:subsample].blank?
        params_key += "_#{params[:subsample]}"
      end
      render_cluster_url(accession: params[:accession], study_name: params[:study_name]) + params_key
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
