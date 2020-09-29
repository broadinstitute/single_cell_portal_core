Rails.application.routes.draw do
  # bare domain redirect to homepage
  get '/', to:redirect('/single_cell', status: 302)

  # For details on the DSL available within this file, see http://guides.rubyonrails.org/routing.html
  scope 'single_cell' do
    # API Routes
    namespace :api do
      mount SwaggerUiEngine::Engine, at: '/'
      namespace :v1 do
        resources :api_docs, only: :index
        namespace :schemas do
          get 'studies'
          get 'study_files'
          get 'study_file_bundles'
          get 'study_shares'
          get 'directory_listings'
        end
        # convention metadata schemas endpoints
        scope :metadata_schemas do
          get '/', to: 'metadata_schemas#index', as: :metadata_schemas
          get ':project_name/:version/:schema_format', to: 'metadata_schemas#load_schema', as: :metadata_schemas_load_convention_schema,
              constraints: {version: /.*/}
        end
        resources :taxons, only: [:index, :show]
        resources :studies, only: [:index, :show, :create, :update, :destroy] do
          post 'study_files/bundle', to: 'study_files#bundle', as: :study_files_bundle_files
          resources :study_files, only: [:index, :show, :create, :update, :destroy] do
            member do
              post 'parse', to: 'study_files#parse'
            end
          end
          resources :study_file_bundles, only: [:index, :show, :create, :destroy]
          resources :study_shares, only: [:index, :show, :create, :update, :destroy]
          resources :directory_listings, only: [:index, :show, :create, :update, :destroy]
          resources :external_resources, only: [:index, :show, :create, :update, :destroy]
          member do
            post 'sync', to: 'studies#sync_study'
          end
          resources :expression_data, only: [:show], param: :data_type
        end

        get 'status', to: 'status#index'
        scope :site do
          get 'studies', to: 'site#studies', as: :site_studies
          get 'studies/:accession', to: 'site#view_study', as: :site_study_view
          get 'studies/:accession/download', to: 'site#download_data', as: :site_study_download_data
          get 'studies/:accession/stream', to: 'site#stream_data', as: :site_study_stream_data
          get 'analyses', to: 'site#analyses', as: :site_analyses
          get 'analyses/:namespace/:name/:snapshot', to: 'site#get_analysis', as: :site_get_analysis
          get 'studies/:accession/analyses/:namespace/:name/:snapshot', to: 'site#get_study_analysis_config', as: :site_get_study_analysis_config
          post 'studies/:accession/analyses/:namespace/:name/:snapshot', to: 'site#submit_study_analysis', as: :site_submit_study_analysis
          get 'studies/:accession/submissions', to: 'site#get_study_submissions', as: :site_get_study_submissions
          get 'studies/:accession/submissions/:submission_id', to: 'site#get_study_submission', as: :site_get_study_submission
          get 'studies/:accession/submissions/:submission_id/sync', to: 'site#sync_submission_outputs', as: :site_sync_submission_outputs
          delete 'studies/:accession/submissions/:submission_id', to: 'site#get_study_submission', as: :site_abort_study_submission
          delete 'studies/:accession/submissions/:submission_id/remove', to: 'site#get_study_submission_dir', as: :site_delete_study_submission_dir
        end
        scope :search do
          get 'facets', to: 'search#facets', as: :search_facets
          get 'facet_filters', to: 'search#facet_filters', as: :search_facet_filters
          post 'auth_code', to: 'search#create_auth_code', as: :create_auth_code
          get 'bulk_download', to: 'search#bulk_download', as: :search_bulk_download
          get 'bulk_download_size', to: 'search#bulk_download_size', as: :search_bulk_download_size
          get '/', to: 'search#index', as: :search
        end
      end
    end

    # portal admin actions
    post 'admin/reset_user_download_quotas', to: 'admin_configurations#reset_user_download_quotas',
         as: :reset_user_download_quotas
    post 'admin/restart_locked_jobs', to: 'admin_configurations#restart_locked_jobs', as: :restart_locked_jobs
    post 'admin/firecloud_access', to: 'admin_configurations#manage_firecloud_access', as: :manage_firecloud_access
    post 'admin/refresh_api_connections', to: 'admin_configurations#refresh_api_connections', as: :refresh_api_connections
    get 'admin/service_account', to: 'admin_configurations#get_service_account_profile', as: :get_service_account_profile
    post 'admin/service_account', to: 'admin_configurations#update_service_account_profile', as: :update_service_account_profile
    get 'admin/users/:id/edit', to: 'admin_configurations#edit_user', as: :edit_user
    match 'admin/users/:id', to: 'admin_configurations#update_user', via: [:post, :patch], as: :update_user
    get 'admin/email_users/compose', to: 'admin_configurations#compose_users_email', as: :compose_users_email
    post 'admin/email_users/compose', to: 'admin_configurations#deliver_users_email', as: :deliver_users_email
    get 'admin/firecloud_api_status', to: 'admin_configurations#firecloud_api_status', as: :firecloud_api_status
    get 'admin/create_portal_user_group', to: 'admin_configurations#create_portal_user_group', as: :create_portal_user_group
    get 'admin/sync_portal_user_group', to: 'admin_configurations#sync_portal_user_group', as: :sync_portal_user_group
    get 'admin/deployment' , to: 'admin_configurations#view_deployment', as: :view_deployment
    post 'admin/deployment', to: 'admin_configurations#create_deployment_notification', as: :create_deployment_notification
    delete 'admin/deployment', to: 'admin_configurations#delete_deployment_notification', as: :delete_deployment_notification
    resources :admin_configurations, path: 'admin'
    resources :preset_searches

    resources :taxons, path: 'species'
    get 'species/:id/download_genome_annotation', to: 'taxons#download_genome_annotation', as: :download_genome_annotation
    post 'species/upload/from_file', to: 'taxons#upload_species_list', as: :upload_species_list

    # branding groups
    resources :branding_groups

    # analysis configurations
    get 'analysis_configurations/load_associated_model', to: 'analysis_configurations#load_associated_model',
        as: :load_associated_model
    get 'analysis_configurations/load_associated_model_filter_types', to: 'analysis_configurations#load_associated_model_filter_types',
        as: :load_associated_model_filter_types
    get 'analysis_configurations/load_associated_model_filter_values', to: 'analysis_configurations#load_associated_model_filter_values',
        as: :load_associated_model_filter_values
    resources :analysis_configurations, except: [:edit] do
      member do
        put 'reset_analysis_parameters', to: 'analysis_configurations#reset_analysis_parameters', as: :reset_analysis_parameters
        match 'analysis_parameters/:analysis_parameter_id', via: [:post, :put, :patch],
              to: 'analysis_configurations#update_analysis_parameter', as: :update_analysis_parameter
        delete 'analysis_parameters/:analysis_parameter_id', to: 'analysis_configurations#destroy_analysis_parameter',
               as: :destroy_analysis_parameter
        get 'submission_preview', to: 'analysis_configurations#submission_preview', as: :submission_preview
        post 'submission_preview', to: 'analysis_configurations#load_study_for_submission_preview', as: :load_study_for_submission_preview
      end
    end

    # study reporter actions
    get 'reports', to: 'reports#index', as: :reports
    get 'reports/report_request', to: 'reports#report_request', as: :report_request
    post 'reports/report_request', to: 'reports#submit_report_request', as: :submit_report_request
    get 'reports/export_submission_report', to: 'reports#export_submission_report', as: :export_submission_report

    # firecloud billing project actions
    get 'billing_projects', to: 'billing_projects#index', as: :billing_projects
    post 'billing_projects/create', to: 'billing_projects#create', as: :create_billing_project
    get 'billing_projects/:project_name', to: 'billing_projects#show_users', as: :show_billing_project_users
    get 'billing_projects/:project_name/new_user', to: 'billing_projects#new_user', as: :new_billing_project_user
    post 'billing_projects/:project_name/add_user', to: 'billing_projects#create_user', as: :create_billing_project_user
    delete 'billing_projects/:project_name/:role/:email', to: 'billing_projects#delete_user',
           as: :delete_billing_project_user, constraints: {email: /.*/}
    get 'billing_projects/:project_name/storage_estimate', to: 'billing_projects#storage_estimate',
        as: :billing_project_storage_estimate
    get 'billing_projects/:project_name/workspaces', to: 'billing_projects#workspaces', as: :billing_project_workspaces
    get 'billing_projects/:project_name/workspaces/:study_name', to: 'billing_projects#edit_workspace_computes',
        as: :edit_workspace_computes
    post 'billing_projects/:project_name/workspaces/:study_name', to: 'billing_projects#update_workspace_computes',
         as: :update_workspace_computes

    # study admin actions
    # mount Ckeditor::Engine => 'ckeditor'
    devise_for :users, :controllers => { :omniauth_callbacks => 'users/omniauth_callbacks' }
    resources :studies do
      member do
        get 'upload', to: 'studies#initialize_study', as: :initialize
        get 'sync', to: 'studies#sync_study', as: :sync
        get 'sync/:submission_id', to: 'studies#sync_submission_outputs', as: :sync_submission_outputs
        patch 'upload', to: 'studies#do_upload'
        get 'resume_upload', to: 'studies#resume_upload'
        patch 'update_status', to: 'studies#update_status'
        get 'retrieve_wizard_upload', to: 'studies#retrieve_wizard_upload', as: :retrieve_wizard_upload
        get 'study_files/new', to: 'studies#new_study_file', as: :new_study_file
        match 'study_files', to: 'studies#update_study_file', via: [:post, :patch], as: :update_study_file
        match 'update_synced_file', to: 'studies#update_study_file_from_sync', via: [:post, :patch],
              as: :update_study_file_from_sync
        match 'sync_study_file', to: 'studies#sync_study_file', via: [:post, :patch], as: :sync_study_file
        match 'sync_orphaned_study_file', to: 'studies#sync_orphaned_study_file', via: [:post, :patch],
              as: :sync_orphaned_study_file
        match 'sync_directory_listing', to: 'studies#sync_directory_listing', via: [:post, :patch],
              as: :sync_directory_listing
        post 'send_to_firecloud', to: 'studies#send_to_firecloud', as: :send_to_firecloud
        delete 'study_files/:study_file_id', to: 'studies#delete_study_file', as: :delete_study_file
        delete 'study_files/unsync/:study_file_id', to: 'studies#unsync_study_file', as: :unsync_study_file
        delete 'directory_listings/:directory_listing_id', to: 'studies#delete_directory_listing',
               as: :delete_directory_listing
        post 'parse', to: 'studies#parse', as: :parse_study_file
        post 'initialize_bundled_file', to: 'studies#initialize_bundled_file', as: 'initialize_bundled_file'
        get 'load_annotation_options', to: 'studies#load_annotation_options', as: :load_annotation_options
        post 'update_default_options', to: 'studies#update_default_options', as: :update_default_options
      end
    end

    # user annotation actions
    resources :user_annotations, only: [:index, :edit, :update, :destroy]
    get 'download_user_annotation/:id', to: 'user_annotations#download_user_annotation', as: :download_user_annotation
    get 'publish_to_study/:id', to: 'user_annotations#publish_to_study', as: :publish_to_study

    # public/private file download links (redirect to signed_urls from Google)
    get 'data/public/:accession/:study_name', to: 'site#download_file', as: :download_file
    get 'data/private/:accession/:study_name', to: 'studies#download_private_file', as: :download_private_file

    post 'totat', to: 'site#create_totat', as: :create_totat
    get 'bulk_data/:accession/:study_name/:download_object/:totat', to: 'site#download_bulk_files', as: :download_bulk_files,
        constraints: {filename: /.*/}

    # user account actions
    get 'profile/:id', to: 'profiles#show', as: :view_profile
    match 'profile/:id', to: 'profiles#update', via: [:post, :patch], as: :update_profile
    match 'profile/:id/subscriptions/share/:study_share_id', to: 'profiles#update_share_subscription', via: [:post, :patch],
          as: :update_share_subscription
    match 'profile/:id/subscriptions/study/:study_id', to: 'profiles#update_study_subscription', via: [:post, :patch],
          as: :update_study_subscription
    post 'profile/:id/firecloud_profile', to: 'profiles#update_firecloud_profile', as: :update_user_firecloud_profile
    get 'profile/:id/accept_tos', to: 'profiles#accept_tos', as: :accept_tos
    post 'profile/:id/accept_tos', to: 'profiles#record_tos_action', as: :record_tos_action

    # data viewing actions
    get 'study/:identifier', to: 'site#legacy_study', as: :legacy_study
    get 'study/:accession/:study_name', to: 'site#study', as: :view_study
    get 'study/:accession/:study_name/edit_study_description', to: 'site#edit_study_description', as: :edit_study_description
    match 'study/:accession/:study_name/update_settings', to: 'site#update_study_settings', via: [:post, :patch], as: :update_study_settings
    get 'study/:accession/:study_name/render_cluster', to: 'site#render_cluster', as: :render_cluster
    get 'study/:accession/:study_name/get_new_annotations', to: 'site#get_new_annotations', as: :get_new_annotations
    post 'study/:accession/:study_name/search', to: 'site#search_genes', as: :search_genes
    get 'study/:accession/:study_name/gene_expression/:gene/', to: 'site#view_gene_expression', as: :view_gene_expression,
        constraints: {gene: /.*/}
    get 'study/:accession/:study_name/render_gene_expression_plots/:gene/', to: 'site#render_gene_expression_plots',
        as: :render_gene_expression_plots, constraints: {gene: /.*/}
    get 'study/:accession/:study_name/render_global_gene_expression_plots/:gene/', to: 'site#render_global_gene_expression_plots',
        as: :render_global_gene_expression_plots, constraints: {gene: /.*/}
    get 'study/:accession/:study_name/gene_expression', to: 'site#view_gene_expression_heatmap', as: :view_gene_expression_heatmap
    get 'study/:accession/:study_name/gene_set_expression', to: 'site#view_gene_set_expression', as: :view_gene_set_expression
    get 'study/:accession/:study_name/render_gene_set_expression_plots', to: 'site#render_gene_set_expression_plots',
        as: :render_gene_set_expression_plots
    get 'study/:accession/:study_name/expression_query', to: 'site#expression_query', as: :expression_query
    get 'study/:accession/:study_name/annotation_query', to: 'site#annotation_query', as: :annotation_query
    get 'study/:accession/:study_name/annotation_values', to: 'site#annotation_values', as: :annotation_values
    post 'study/:accession/:study_name/precomputed_gene_expression', to: 'site#search_precomputed_results', as: :search_precomputed_results
    get 'study/:accession/:study_name/precomputed_gene_expression', to: 'site#view_precomputed_gene_expression_heatmap',
        as: :view_precomputed_gene_expression_heatmap
    get 'study/:accession/:study_name/precomputed_results', to: 'site#precomputed_results', as: :precomputed_results

    # user annotation actions
    post 'study/:accession/:study_name/create_user_annotations', to: 'site#create_user_annotations', as: :create_user_annotations
    get 'study/:accession/:study_name/show_user_annotations_form', to: 'site#show_user_annotations_form', as: :show_user_annotations_form

    # workflow actions
    get 'study/:accession/:study_name/get_fastq_files', to: 'site#get_fastq_files', as: :get_fastq_files
    get 'study/:accession/:study_name/workspace_samples', to: 'site#get_workspace_samples', as: :get_workspace_samples
    get 'study/:accession/:study_name/submissions', to: 'site#get_workspace_submissions', as: :get_workspace_submissions
    post 'study/:accession/:study_name/submissions', to: 'site#create_workspace_submission', as: :create_workspace_submission
    get 'study/:accession/:study_name/submissions/:submission_id', to: 'site#get_submission_workflow', as: :get_submission_workflow
    get 'study/:accession/:study_name/submissions/:submission_id/metadata', to: 'site#get_submission_metadata',
        as: :get_submission_metadata
    get 'study/:accession/:study_name/submissions/:submission_id/metadata_export', to: 'site#export_submission_metadata',
        as: :export_submission_metadata
    delete 'study/:accession/:study_name/submissions/:submission_id', to: 'site#abort_submission_workflow',
           as: :abort_submission_workflow
    delete 'study/:accession/:study_name/submissions/:submission_id/outputs', to: 'site#delete_submission_files',
           as: :delete_submission_files
    get 'study/:accession/:study_name/submissions/:submission_id/outputs', to: 'site#get_submission_outputs', as: :get_submission_outputs
    get 'study/:accession/:study_name/submissions/:submission_id/errors', to: 'site#get_submission_errors', as: :get_submission_errors
    post 'study/:accession/:study_name/workspace_samples', to: 'site#update_workspace_samples', as: :update_workspace_samples
    post 'study/:accession/:study_name/delete_workspace_samples', to: 'site#delete_workspace_samples', as: :delete_workspace_samples
    get 'view_workflow_wdl', to: 'site#view_workflow_wdl', as: :view_workflow_wdl
    get 'workflow_options', to: 'site#get_workflow_options', as: :get_workflow_options
    get 'analysis_configuration', to: 'site#get_analysis_configuration', as: :get_analysis_configuration
    get 'genome_assemblies', to: 'site#get_taxon_assemblies', as: :get_taxon_assemblies
    get 'taxon', to: 'site#get_taxon', as: :get_taxon

    # base actions
    get 'search', to: 'site#search', as: :search
    post 'get_viewable_studies', to: 'site#get_viewable_studies', as: :get_viewable_studies
    post 'search_all_genes', to: 'site#search_all_genes', as: :search_all_genes
    get 'log_action', to: 'site#log_action', as: :log_action
    get 'privacy_policy', to: 'site#privacy_policy', as: :privacy_policy
    get 'terms_of_service', to: 'site#terms_of_service', as: :terms_of_service

    get 'covid19', to: 'site#covid19'

    get '/', to: 'site#index', as: :site
    post '/', to: 'site#index'

    # let react routing handle app and all subpaths under 'app'
    get 'app', to: 'site#index'
    get 'app/*path', to: 'site#index'

    root to: 'site#index'
  end
end
