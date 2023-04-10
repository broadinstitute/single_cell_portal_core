module ApplicationHelper

  # overriding link_to to preserve branding_group params
  def scp_link_to(name, url, html_options={}, &block)
    if url.start_with?('https') || url.start_with?('/')
      current_url = request.fullpath
      if current_url.include?('scpbr=')
        current_params = current_url.split('?').last.split('&')
        current_project = current_params.detect {|p| p =~ /scpbr=/}.gsub(/scpbr=/, '')
        if !url.include?('?')
          url += "?scpbr=#{current_project}"
        else
          url += "&scpbr=#{current_project}"
        end
      end
    end
    link_to(name, url, html_options, &block)
  end

  #
  def scp_url_for(url, branding_group)
    formatted_url = url.dup
    query_operator = url.include?('?') ? '&' : '?'
    if branding_group.present?
      formatted_url += "#{query_operator}scpbr=#{branding_group}"
    end
    formatted_url
  end

  # set gene search placeholder value based on parameters
  def set_search_value
    if params[:search]
      if params[:search][:gene]
        @gene
      elsif !params[:search][:genes].nil?
        @genes.map{|gene| gene['name']}.join(' ')
      end
    elsif params[:gene]
      params[:gene]
    else
      nil
    end
  end

  # create javascript-safe url with parameters
  def javascript_safe_url(url)
    # remove utf8=✓& from url to avoid formatting errors
    CGI.unescape(url.gsub(/utf8=%E2%9C%93&/, '')).html_safe
  end

  # construct nav menu breadcrumbs
  def set_breadcrumbs
    breadcrumbs = []
    if controller_name == 'site'
      if @study
        breadcrumbs << {title: "Study overview", link: view_study_path(accession: @study.accession, study_name: @study.url_safe_name)}
      end
      case action_name
        when 'view_gene_expression'
          breadcrumbs << {title: "Gene expression <span class='badge'>#{params[:gene]}</span>", link: 'javascript:;'}
        when 'view_gene_set_expression'
          breadcrumbs << {title: "Gene set expression <span class='badge'>Multiple</span>", link: 'javascript:;'}
        when 'view_gene_expression_heatmap'
          breadcrumbs << {title: "Gene expression <span class='badge'>Multiple</span>", link: 'javascript:;'}
        when 'view_precomputed_gene_expression_heatmap'
          breadcrumbs << {title: "Gene expression <span class='badge'>#{params[:precomputed]}</span>", link: 'javascript:;'}
        when 'view_all_gene_expression_heatmap'
          breadcrumbs << {title: "Gene expression <span class='badge'>All</span>", link: 'javascript:;'}
      end
    elsif controller_name == 'studies'
      breadcrumbs << {title: "My studies", link: studies_path}
      case action_name
        when 'new'
          breadcrumbs << {title: "New study", link: 'javascript:;'}
        when 'edit'
          breadcrumbs << {title: "Editing '#{truncate(@study.name, length: 20)}'", link: 'javascript:;'}
        when 'show'
          breadcrumbs << {title: "Showing '#{truncate(@study.name, length: 20)}'", link: 'javascript:;'}
        when 'initialize_study'
          breadcrumbs << {title: "Upload/Edit study data", link: 'javascript:;'}
        when 'sync_study'
          breadcrumbs << {title: "Synchronize workspace", link: 'javascript:;'}
      end
    elsif controller_name == 'admin_configurations'
      breadcrumbs << {title: 'Admin control panel', link: admin_configurations_path}
      case action_name
        when 'new'
          breadcrumbs << {title: "New config option", link: 'javascript:;'}
        when 'edit'
          breadcrumbs << {title: "Editing '#{@admin_configuration.config_type}'", link: 'javascript:;'}
      end
    elsif controller_name == 'billing_projects'
      breadcrumbs << {title: "My billing projects", link: billing_projects_path}
      case action_name
        when 'new_user'
          breadcrumbs << {title: "Add billing project user", link: 'javascript:;'}
        when 'workspaces'
          breadcrumbs << {title: "Workspaces <span class='badge'>#{params[:project_name]}</span>", link: 'javascript:;'}
        when 'storage_estimate'
          breadcrumbs << {title: "Storage costs <span class='badge'>#{params[:project_name]}</span>", link: 'javascript:;'}
        when 'edit_workspace_computes'
          breadcrumbs << {title: "Editing compute permissions <span class='badge'>#{truncate(params[:study_name], length: 10)}</span>", link: 'javascript:;'}
      end
    end
    breadcrumbs
  end

  # construct a dropdown for navigating to single gene-level expression views
  def load_gene_nav(genes)
    nav = [['All queried genes', '']]
    genes.each do |gene|
      nav << [gene['gene'], view_gene_expression_path(accession: params[:accession], study_name: params[:study_name], gene: gene['gene'])]
    end
    nav
  end

  # TODO eweitz 2017-12-20: Can the 'set_foo_value' methods below be abstracted?
  # They have a similar form, and might be more succinctly expressed in one method that uses
  # a hash to map parameter names to default values, and returns the deterministic parameter value.
  # Refactoring might be worthwhile after ensuring the redundant-but-familiar methods pass all tests.

  # method to set cluster value based on options and parameters
  # will fall back to default cluster if nothing is specified
  def set_cluster_value(selected_study, parameters)
    if !parameters[:gene_set_cluster].nil?
      parameters[:gene_set_cluster]
    elsif !parameters[:cluster].nil?
      parameters[:cluster]
    else
      selected_study.default_cluster.name
    end
  end

  # method to set annotation value by parameters or load a 'default' annotation when first loading a study (none have been selected yet)
  # will fall back to default annotation if nothing is specified
  def set_annotation_value(selected_study, parameters)
    if !parameters[:gene_set_annotation].nil?
      parameters[:gene_set_annotation]
    elsif !parameters[:annotation].nil?
      parameters[:annotation]
    else
      selected_study.default_annotation
    end
  end

  # method to set annotation value by parameters or load a 'default' annotation when first loading a study (none have been selected yet)
  # will fall back to default annotation if nothing is specified
  def set_subsample_value(parameters)
    if !parameters[:gene_set_subsample].nil?
      parameters[:gene_set_subsample].to_i
    elsif !parameters[:subsample].nil?
      parameters[:subsample].to_i
    else
      'All Cells'
    end
  end

  ### Beginning of 'Distribution' view options
  def set_distribution_plot_type_value(parameters)
    if !parameters[:gene_set_plot_type].nil?
      parameters[:gene_set_plot_type]
    elsif !parameters[:plot_type].nil?
      parameters[:plot_type]
    else
      'violin'
    end
  end

  def set_distribution_jitter_value(parameters)
    if !parameters[:gene_set_jitter].nil?
      parameters[:gene_set_jitter]
    elsif !parameters[:jitter].nil?
      parameters[:jitter]
    else
      'all'
    end
  end
  def set_boxpoints_value(parameters)
    if !parameters[:gene_set_boxpoints].nil?
      parameters[:gene_set_boxpoints]
    elsif !parameters[:boxpoints].nil?
      parameters[:boxpoints]
    else
      'all'
    end
  end
  ### End of 'Distribution' view options

  ### Beginning of 'Heatmap' view options
  def set_heatmap_row_centering_value(parameters)
    if !parameters[:gene_set_heatmap_row_centering].nil?
      parameters[:gene_set_heatmap_row_centering]
    elsif !parameters[:heatmap_row_centering].nil?
      parameters[:heatmap_row_centering]
    else
      ''
    end
  end

  def set_heatmap_size_value(parameters)
    if !parameters[:gene_set_heatmap_size].nil?
      parameters[:gene_set_heatmap_size]
    elsif !parameters[:heatmap_size].nil?
    parameters[:heatmap_size]
    else
      ''
    end
  end
  ### End of 'Heatmap' view options

  # set colorscale value
  def set_colorscale_value(selected_study, parameters)
    if !parameters[:colorscale].blank?
      parameters[:colorscale]
    elsif selected_study.default_cluster.name == parameters[:cluster] && !selected_study.default_color_profile.blank?
      selected_study.default_color_profile
    elsif params[:cluster].blank? && !selected_study.default_color_profile.blank? # no cluster requested, so go to defaults
      selected_study.default_color_profile
    else
      'Reds'
    end
  end

  # return an array of values to use for subsampling dropdown scaled to number of cells in study
  # only options allowed are 1000, 10000, 20000, and 100000
  # will only provide options if subsampling has completed for a cluster
  def subsampling_options(cluster)
    ClusterVizService.subsampling_options(cluster)
  end

  # get a label for a workflow status code
  def submission_status_label(status)
    case status
      when 'Queued'
        label_class = 'default'
      when 'Submitted'
        label_class = 'info'
      when 'Running'
        label_class = 'primary'
      when 'Done'
        label_class = 'success'
      when 'Aborting'
        label_class = 'warning'
      when 'Aborted'
        label_class = 'danger'
      else
        label_class = 'default'
    end
    "<span class='label label-#{label_class}'>#{status}</span>".html_safe
  end

  # get a label for a workflow status code
  def workflow_status_labels(workflow_statuses)
    labels = []
    workflow_statuses.keys.each do |status|
      case status
        when 'Submitted'
          label_class = 'info'
        when 'Launching'
          label_class = 'info'
        when 'Running'
          label_class = 'primary'
        when 'Succeeded'
          label_class = 'success'
        when 'Failed'
          label_class = 'danger'
        else
          label_class = 'default'
      end
      labels << "<span class='label label-#{label_class}'>#{status}</span>"
    end
    labels.join("<br />").html_safe
  end

  # get a UTC timestamp in local time, formatted all purty-like
  def local_timestamp(utc_time)
    Time.zone.parse(utc_time).strftime("%F %R")
  end

  # get actions links for a workflow submission
  def get_submission_actions(submission, study)
    actions = []
    # submission is still queued or running
    if %w(Queued Submitted Running).include?(submission['status'])
      actions << link_to("<i class='fas fa-fw fa-times'></i> Abort".html_safe, '#',
                         class: 'btn btn-xs btn-block btn-danger abort-submission', title: 'Stop execution of this workflow',
                         data: {
                             toggle: 'tooltip',
                             url: abort_submission_workflow_path(accession: study.accession, study_name: study.url_safe_name,
                                                                 submission_id: submission['submissionId']),
                             id: submission['submissionId']
                         })
    end
    # submission has completed successfully
    if submission['status'] == 'Done' && submission['workflowStatuses'].keys.include?('Succeeded')
      actions << link_to("<i class='fas fa-fw fa-code'></i> View Run Info".html_safe, 'javascript:;',
                         class: 'btn btn-xs btn-block btn-info view-submission-metadata', title: 'View HCA-formatted analysis metadata',
                         data: {
                             toggle: 'tooltip',
                             url: get_submission_metadata_path(accession: study.accession, study_name: study.url_safe_name,
                                                               submission_id: submission['submissionId']),
                             id: submission['submissionId']
                         })
      actions << scp_link_to("<i class='fas fa-fw fa-sync-alt'></i> Sync".html_safe,
                         sync_submission_outputs_study_path(
                                 id: @study.id, submission_id: submission['submissionId'],
                                 configuration_namespace: submission['methodConfigurationNamespace'],
                                 configuration_name: submission['methodConfigurationName']),
                         class: 'btn btn-xs btn-block btn-warning sync-submission-outputs',
                         title: 'Sync outputs from this run back to study', data: {toggle: 'tooltip', id: submission['submissionId']})
    end
    # submission has failed
    if %w(Done Aborted).include?(submission['status']) && submission['workflowStatuses'].keys.include?('Failed')
      actions << link_to("<i class='fas fa-fw fa-exclamation-triangle'></i> Show Errors".html_safe, 'javascript:;',
                         class: 'btn btn-xs btn-block btn-danger get-submission-errors', title: 'View errors for this run',
                         data: {
                             toggle: 'tooltip',
                             url: get_submission_workflow_path(accession: study.accession, study_name: study.url_safe_name,
                                                               submission_id: submission['submissionId']),
                             id: submission['submissionId']
                         })
    end
    # delete action to always load when completed
    if %w(Done Aborted).include?(submission['status'])
      actions << link_to("<i class='fas fa-fw fa-trash'></i> Delete Submission".html_safe, 'javascript:;',
                         class: 'btn btn-xs btn-block btn-danger delete-submission-files',
                         title: 'Remove submission from list and delete all files from submission directory',
                         data: {
                             toggle: 'tooltip',
                             url: delete_submission_files_path(accession: study.accession, study_name: study.url_safe_name,
                                                               submission_id: submission['submissionId']),
                             id: submission['submissionId']})
    end
    actions.join(" ").html_safe
  end

  # return a formatted label for a study's intializatin status
  def get_initialized_icon(initialized)
    initialized ? "<small data-toggle='tooltip' title='Visualizations are enabled'><span class='fas fa-fw fa-eye text-success'></span></small>".html_safe : "<small data-toggle='tooltip' title='Visualizations are disabled'><span class='fas fa-fw fa-eye text-danger'></span></small>".html_safe
  end

  # convert an email address into string that can be used as a DOM element id
  def email_as_id(email)
    email.gsub(/[@\.]/, '-')
  end

  # Return an access token for viewing GCS objects client side, depending on study privacy
  def get_read_access_token(study, user)
    RequestUtils.get_read_access_token(study, user)
  end

  # Return the user's access token for bulk download of faceted search results
  def get_user_access_token(user)
    if user.present?
      user.valid_access_token.try(:[], :access_token)
    end
  end

  def pluralize_without_count(count, noun, text=nil)
    count.to_i == 1 ? "#{noun}#{text}" : "#{noun.pluralize}#{text}"
  end

  def get_page_name
    MetricsService.get_page_name(controller_name, action_name)
  end

  # helper to add a red * to a form field label
  def label_with_asterisk(label_name)
    "#{label_name} <i class='text-danger'>*</i>".html_safe
  end

  # helper for rendering split chunks tags with a nonce
  # based off of nonced_javascript_pack_tag in secure_headers
  # see https://github.com/github/secure_headers/blob/main/lib/secure_headers/view_helper.rb
  def nonced_javascript_pack_with_chunks_tag(*args, &block)
    opts = extract_options(args).merge(nonce: _content_security_policy_nonce(:script))

    javascript_packs_with_chunks_tag(*args, **opts, &block)
  end

  # helper for rendering Vite javascript assets with a nonce
  # based off of nonced_javascript_pack_tag in secure_headers
  # see https://github.com/github/secure_headers/blob/main/lib/secure_headers/view_helper.rb
  def nonced_vite_javascript_tag(*args, &block)
    opts = extract_options(args).merge(nonce: _content_security_policy_nonce(:script))
    begin
      vite_javascript_tag(*args, **opts, &block)
    rescue Exception => e
      # the vite_javascript tag invocation will intermittently fail in CI environment for mysterious reasons
      # so we catch the failure here, and swallow it if we're in CI
      unless Rails.env.test?
        raise e
      end
      Rails.logger.info("Vite bundle is not available in testing -- skipping")
      nil
    end
  end

  # helper for rendering Vite javascript assets with a nonce
  # based off of nonced_javascript_pack_tag in secure_headers
  # see https://github.com/github/secure_headers/blob/main/lib/secure_headers/view_helper.rb
  def nonced_vite_client_tag(*args, &block)
    tag_content = vite_client_tag(*args, &block)
    nonce = _content_security_policy_nonce(:script)
    tag_content&.gsub('module"', 'module" nonce="' + nonce + '"')&.gsub('localhost', 'https://localhost')&.html_safe
  end

  def nonced_vite_react_refresh_tag(*args, &block)
    tag_content = vite_react_refresh_tag(*args, &block)
    nonce = _content_security_policy_nonce(:script)
    tag_content&.gsub('module"', 'module" nonce="' + nonce + '"')&.gsub('localhost', 'https://localhost')&.html_safe
  end
end
