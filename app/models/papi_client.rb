##
# PapiClient: a lightweight wrapper around the Google Cloud Genomics V2 Alpha API for submitting/reporting
# scp-ingest-service jobs to ingest user-uploaded data
#
# requires: googleauth, google-api-client, FireCloudClient class (for bucket access)
#
# Author::  Jon Bistline  (mailto:bistline@broadinstitute.org)
class PapiClient
  extend ServiceAccountManager

  attr_accessor :project, :service_account_credentials, :service

  # Google authentication scopes necessary for running pipelines
  GOOGLE_SCOPES = %w(https://www.googleapis.com/auth/cloud-platform)

  # Network and sub-network names, if needed
  GCP_NETWORK_NAME = ENV['GCP_NETWORK_NAME']
  GCP_SUB_NETWORK_NAME = ENV['GCP_SUB_NETWORK_NAME']

   # List of scp-ingest-pipeline actions and their allowed file types
  FILE_TYPES_BY_ACTION = {
    ingest_expression: ['Expression Matrix', 'MM Coordinate Matrix'],
    ingest_cluster: %w[Cluster AnnData],
    ingest_cell_metadata: %w[Metadata AnnData],
    ingest_subsample: ['Cluster'],
    differential_expression: ['Cluster'],
    render_expression_arrays: ['Cluster'],
    image_pipeline: ['Cluster'],
    ingest_anndata: ['AnnData']
  }.freeze

  # jobs that require custom virtual machine types (e.g. more RAM, CPU)
  CUSTOM_VM_ACTIONS = %i[differential_expression render_expression_arrays image_pipeline].freeze

  # default GCE machine_type
  DEFAULT_MACHINE_TYPE = 'n1-highmem-4'.freeze

  # regex to sanitize label values for VMs/pipelines
  # alphanumeric plus - and _
  LABEL_SANITIZER = /[^a-zA-Z\d\-_]/

  # Default constructor for PapiClient
  #
  # * *params*
  #   - +project+: (String) => GCP Project to use (can be overridden by other parameters)
  #   - +service_account_credentials+: (Path) => Absolute filepath to service account credentials
  # * *return*
  #   - +PapiClient+
  def initialize(project = self.class.compute_project, service_account_credentials = self.class.get_primary_keyfile)
    credentials = {
      scope: GOOGLE_SCOPES,
      json_key_io: File.open(service_account_credentials)
    }

    authorizer = Google::Auth::ServiceAccountCredentials.make_creds(credentials)
    genomics_service = Google::Apis::GenomicsV2alpha1::GenomicsService.new
    genomics_service.authorization = authorizer

    self.project = project
    self.service_account_credentials = service_account_credentials
    self.service = genomics_service
  end

  # Return the service account email
  #
  # * *return*
  #   - (String) Service Account email
  def issuer
    service.authorization.issuer
  end

  # Returns a list of all pipelines run in this project
  # Note: the 'filter' parameter is broken for this method and is not supported here
  #
  # * *params*
  #   - +page_token+ (String) => Request next page of results using token
  #
  # * *return*
  #   - (Google::Apis::GenomicsV2alpha1::ListOperationsResponse)
  #
  # * *raises*
  #   - (Google::Apis::ServerError) => An error occurred on the server and the request can be retried
  #   - (Google::Apis::ClientError) =>  The request is invalid and should not be retried without modification
  #   - (Google::Apis::AuthorizationError) => Authorization is required
  def list_pipelines(page_token: nil)
    service.list_project_operations("projects/#{project}/operations", page_token: page_token)
  end

  # Runs a pipeline.  Will call sub-methods to instantiate required objects to pass to
  # Google::Apis::GenomicsV2alpha1::GenomicsService.run_pipeline
  #
  # * *params*
  #   - +study_file+ (StudyFile) => File to be ingested
  #   - +user+ (User) => User performing ingest action
  #   - +action+ (String) => Action that is being performed, maps to Ingest pipeline action
  #     (e.g. 'ingest_cell_metadata', 'subsample')
  #   - +params_object+ (Class) => Class containing parameters for PAPI job (like DifferentialExpressionParameters)
  #                                must include Parameterizable concern for to_options_array support
  #
  # * *return*
  #   - (Google::Apis::GenomicsV2alpha1::Operation)
  #
  # * *raises*
  #   - (Google::Apis::ServerError) => An error occurred on the server and the request can be retried
  #   - (Google::Apis::ClientError) =>  The request is invalid and should not be retried without modification
  #   - (Google::Apis::AuthorizationError) => Authorization is required
  def run_pipeline(study_file:, user:, action:, params_object: nil)
    study = study_file.study
    labels = job_labels(action:, study:, study_file:, user:, params_object:)
    # override default VM if required for this action
    if needs_custom_vm?(action)
      custom_vm = create_virtual_machine_object(machine_type: params_object.machine_type, labels: labels)
      resources = create_resources_object(regions: ['us-central1'], vm: custom_vm)
    else
      resources = create_resources_object(regions: ['us-central1'], labels: labels)
    end

    user_metrics_uuid = user.metrics_uuid
    command_line = get_command_line(study_file:, action:, user_metrics_uuid:, params_object:)

    environment = set_environment_variables(action:)
    if params_object.respond_to?(:docker_image) && params_object.docker_image
      action = create_actions_object(
        commands: command_line, environment: environment, image_uri: params_object.docker_image
      )
    else
      action = create_actions_object(commands: command_line, environment: environment)
    end
    pipeline = create_pipeline_object(actions: [action], environment: environment, resources: resources)
    pipeline_request = create_run_pipeline_request_object(pipeline:, labels:)
    Rails.logger.info "Request object sent to Google Pipelines API (PAPI), excluding 'environment' parameters:"
    sanitized_pipeline_request = pipeline_request.to_h[:pipeline].except(:environment)
    sanitized_pipeline_request[:actions] = sanitized_pipeline_request[:actions][0].except(:environment)
    Rails.logger.info sanitized_pipeline_request.to_yaml
    service.run_pipeline(pipeline_request, quota_user: user.id.to_s)
  end

  # Get an existing pipeline run
  #
  # * *params*
  #   - +name+ () => Operation corresponding with a submission of ingest
  #   - +fields+ (String) => Selector specifying which fields to include in a partial response.
  #   - +user+ (User) => User that originally submitted pipeline
  #
  # * *return*
  #   - (Google::Apis::GenomicsV2alpha1::Operation)
  def get_pipeline(name:, fields: nil, user: nil)
    quota_user = user.present? ? user.id.to_s : nil
    service.get_project_operation(name, fields: fields, quota_user: quota_user)
  end

  # Create a run pipeline request object to send to service.run_pipeline
  #
  # * *params*
  #   - +pipeline+ (Google::Apis::GenomicsV2alpha1::Pipeline) => Pipeline object from create_pipeline_object
  #   - +labels+ (Hash) => Hash of key/value pairs to set as the pipeline labels
  #
  # * *return*
  #   - (Google::Apis::GenomicsV2alpha1::RunPipelineRequest)
  def create_run_pipeline_request_object(pipeline:, labels: {})
    Google::Apis::GenomicsV2alpha1::RunPipelineRequest.new(pipeline:, labels:)
  end

  # Create a pipeline object detailing all required information in order to run an ingest job
  #
  # * *params*
  #   - +actions+ (Array<Google::Apis::GenomicsV2alpha1::Action>) => actions to perform, from create_actions_object
  #   - +environment+ (Hash) => Hash of key/value pairs to set as the container env
  #   - +resources+ (Google::Apis::GenomicsV2alpha1::Resources) => Resources object from create_resources_object
  #   - +timeout+ (String) => Maximum runtime of pipeline (defaults to 1 week)
  #
  # * *return*
  #   - (Google::Apis::GenomicsV2alpha1::Pipeline)
  def create_pipeline_object(actions:, environment:, resources:, timeout: nil)
    Google::Apis::GenomicsV2alpha1::Pipeline.new(actions:, environment:, resources:, timeout:)
  end

  # Instantiate actions for pipeline, which holds command line actions, docker information,
  # and information that is passed to run_pipeline.  The Docker image that is pulled for this
  # is referenced from AdminConfiguration.get_ingest_docker_image, which will pull either from
  # and existing configuration object (for non-production environments) or fall back to
  # Rails.application.config.ingest_docker_image
  #
  # * *params*
  #   - +commands+: (Array<String>) => An array of commands to run inside the container
  #   - +environment+: (Hash) => Hash of key/value pairs to set as the container env
  #   - +flags+: (Array<String>) => An array of flags to apply to the action
  #   - +image_uri+: (String) => GCR Docker image to pull, defaults to AdminConfiguration.get_ingest_docker_image
  #   - +labels+: (Hash) => Hash of labels to associate with the action
  #   - +timeout+: (String) => Maximum runtime of action
  #   - +image_uri+: (String) => Override for docker image URI
  #
  #  * *return*
  #   - (Google::Apis::GenomicsV2alpha1::Action)
  def create_actions_object(commands: [], environment: {}, flags: [], labels: {}, timeout: nil, image_uri: nil)
    Google::Apis::GenomicsV2alpha1::Action.new(
      commands: commands,
      environment: environment,
      flags: flags,
      image_uri: image_uri || AdminConfiguration.get_ingest_docker_image,
      labels: labels,
      timeout: timeout
    )
  end

  # Set necessary environment variables for Ingest Pipeline, including:
  #   - +DATABASE_HOST+: IP address of MongoDB server (use MONGO_INTERNAL_IP for connecting inside GCP)
  #   - +MONGODB_USERNAME+: MongoDB user associated with current schema (defaults to single_cell)
  #   - +MONGODB_PASSWORD+: Password for above MongoDB user
  #   - +DATABASE_NAME+: Name of current MongoDB schema as defined by Rails environment
  #   - +GOOGLE_PROJECT_ID+: Name of the GCP project this pipeline is running in
  #   - +SENTRY_DSN+: Sentry Data Source Name (DSN); URL to send Sentry logs to
  #   - +BARD_HOST_URL+: URL for Bard host that proxies Mixpanel
  #   - +NODE_TLS_REJECT_UNAUTHORIZED+: Configure node behavior for self-signed certificates (for :image_pipeline)
  #   - +STAGING_INTERNAL_IP+: Bypasses firewall for staging runs (for :image_pipeline)
  #
  # * *params*
  #   - +action+ (Symbol) => ingest action being performed
  # * *returns*
  #   - (Hash) => Hash of required environment variables
  def set_environment_variables(action: nil)
    vars = {
      'DATABASE_HOST' => ENV['MONGO_INTERNAL_IP'],
      'MONGODB_USERNAME' => 'single_cell',
      'MONGODB_PASSWORD' => ENV['PROD_DATABASE_PASSWORD'],
      'DATABASE_NAME' => Mongoid::Config.clients["default"]["database"],
      'GOOGLE_PROJECT_ID' => project,
      'SENTRY_DSN' => ENV['SENTRY_DSN'],
      'BARD_HOST_URL' => Rails.application.config.bard_host_url
    }
    if action == :image_pipeline
      vars.merge({
        # For staging runs
        'NODE_TLS_REJECT_UNAUTHORIZED' => '0',

        # For staging runs.  More context is in "Networking" section at:
        # https://github.com/broadinstitute/single_cell_portal_core/pull/1632
        'STAGING_INTERNAL_IP' => ENV['APP_INTERNAL_IP']
      })
    else
      vars
    end
  end

  # Instantiate a resources object to tell where to run a pipeline
  #
  # * *params*
  #   - +regions+: (Array<String>) => An array of GCP regions allowed for VM allocation
  #   - +vm+: (Google::Apis::GenomicsV2alpha1::VirtualMachine) => Existing VM config to use, other than default
  #   - +labels+ (Hash) => Key/value pairs of labels for VM
  #
  # * *return*
  #   - (Google::Apis::GenomicsV2alpha1::Resources)
  def create_resources_object(regions:, vm: nil, labels: {})
    Google::Apis::GenomicsV2alpha1::Resources.new(
      project_id: project,
      regions: regions,
      virtual_machine: vm.nil? ? create_virtual_machine_object(labels:) : vm
    )
  end

  # Instantiate a VM object to specify in resources.  Assigns the portal service account to the VM
  # to manage permissions.  If GCP_NETWORK_NAME and GCP_SUBNETWORK_NAME have been set, it will also
  # assign the VM to the corresponding project network.  Otherwise, the VM uses the default network.
  #
  # * *params*
  #   - +machine_type+ (String) => GCP VM machine type (defaults to 'n1-highmem-4': 4 CPU, 26GB RAM)
  #   - +boot_disk_size_gb+ (Integer) => Size of boot disk for VM, in gigabytes (defaults to 100GB)
  #   - +preemptible+ (Boolean) => Indication of whether VM can be preempted (defaults to false)
  #   - +labels+ (Hash) => Key/value pairs of labels for VM
  # * *return*
  #   - (Google::Apis::GenomicsV2alpha1::VirtualMachine)
  def create_virtual_machine_object(machine_type: DEFAULT_MACHINE_TYPE,
                                    boot_disk_size_gb: 300,
                                    preemptible: false,
                                    labels: {})
    virtual_machine = Google::Apis::GenomicsV2alpha1::VirtualMachine.new(
      machine_type: machine_type,
      preemptible: preemptible,
      boot_disk_size_gb: boot_disk_size_gb,
      labels: labels,
      service_account: Google::Apis::GenomicsV2alpha1::ServiceAccount.new(email: issuer, scopes: GOOGLE_SCOPES)
    )
    # assign correct network/sub-network if specified
    if GCP_NETWORK_NAME.present? && GCP_SUB_NETWORK_NAME.present?
      virtual_machine.network = Google::Apis::GenomicsV2alpha1::Network.new(name: GCP_NETWORK_NAME,
                                                                            subnetwork: GCP_SUB_NETWORK_NAME)
    end
    virtual_machine
  end

  # Determine command line to pass to ingest based off of file & action requested
  #
  # * *params*
  #   - +study_file+ (StudyFile) => StudyFile to be ingested
  #   - +action+ (String/Symbol) => Action to perform on ingest
  #   - +params_object+ (Class) => Class containing parameters for PAPI job (like DifferentialExpressionParameters)
  #                                must implement :to_options_array method
  #
  # * *return*
  #   - (Array) Command Line, in Docker "exec" format
  #
  # * *raises*
  #   - (ArgumentError) => The requested StudyFile and action do not correspond with each other, or cannot be run yet
  def get_command_line(study_file:, action:, user_metrics_uuid:, params_object: nil)
    validate_action_by_file(action, study_file)
    study = study_file.study
    command_line = "python ingest_pipeline.py --study-id #{study.id} --study-file-id #{study_file.id} " \
                   "--user-metrics-uuid #{user_metrics_uuid} #{action}"

    case action.to_s
    when 'ingest_expression'
      if study_file.file_type == 'Expression Matrix'
        command_line += " --matrix-file #{study_file.gs_url} --matrix-file-type dense"
      elsif study_file.file_type === 'MM Coordinate Matrix'
        bundled_files = study_file.bundled_files
        genes_file = bundled_files.detect {|f| f.file_type == '10X Genes File'}
        barcodes_file = bundled_files.detect {|f| f.file_type == '10X Barcodes File'}
        command_line += " --matrix-file #{study_file.gs_url} --matrix-file-type mtx" \
                      " --gene-file #{genes_file.gs_url} --barcode-file #{barcodes_file.gs_url}"
      end
    when 'ingest_cell_metadata'
      # skip if parent file is AnnData as params_object will format command line
      command_line += " --cell-metadata-file #{study_file.gs_url} --study-accession #{study.accession} " \
                      "--ingest-cell-metadata" unless study_file.is_anndata?
      if study_file.use_metadata_convention
        command_line += " --validate-convention --bq-dataset #{CellMetadatum::BIGQUERY_DATASET} " \
                        "--bq-table #{CellMetadatum::BIGQUERY_TABLE}"
      end
    when 'ingest_cluster'
      # skip if parent file is AnnData as params_object will format command line
      command_line += " --cluster-file #{study_file.gs_url} --ingest-cluster" unless study_file.is_anndata?
    when 'ingest_subsample'
      metadata_file = study.metadata_file
      command_line += " --cluster-file #{study_file.gs_url} --cell-metadata-file #{metadata_file.gs_url} --subsample"
    when 'differential_expression'
      command_line += " --study-accession #{study.accession}"
    when 'image_pipeline'
      # image_pipeline is node-based, so python command line to this point no longer applies
      command_line = 'node expression-scatter-plots.js'
    end

    # add optional command line arguments based on file type and action
    if params_object.present?
      unless params_object_valid?(params_object)
        raise ArgumentError, "invalid params_object for #{action}: #{params_object.inspect}"
      end

      optional_args = params_object.to_options_array
    else
      optional_args = get_command_line_options(study_file, action)
    end

    # return an array of tokens (Docker expects exec form, which runs without a shell, so cannot be a single command)
    command_line.split + optional_args
  end

  # Assemble any optional command line options for ingest by file type
  #
  # * *params*
  #   - +study_file+ (StudyFile) => File to be ingested
  #   - +action+ (String/Symbol) => Action being performed on file
  #
  # * *returns*
  #   (Array) => Array representation of optional arguments (Docker exec form), based on file type
  def get_command_line_options(study_file, action)
    opts = []
    case study_file.file_type
    when /Matrix/
      if study_file.taxon.present?
        taxon = study_file.taxon
        opts += ["--taxon-name", "#{taxon.scientific_name}", "--taxon-common-name", "#{taxon.common_name}",
                 "--ncbi-taxid", "#{taxon.ncbi_taxid}"]
      end
    when 'Cluster'
      # the name of Cluster files is the same as the name of the cluster object itself
      opts += ["--name", "#{study_file.name}"]
      # add domain ranges if this cluster is being ingested (not needed for subsampling)
      if action.to_sym == :ingest_cluster
        if study_file.get_cluster_domain_ranges.any?
          opts += ["--domain-ranges", "#{sanitize_json(study_file.get_cluster_domain_ranges.to_json)}"]
        else
          opts += ["--domain-ranges", "{}"]
        end
      end
    end
    opts
  end

  # set labels for pipeline request/virtual machine
  #
  # * *params*
  #   - +action+ (String, Symbol) => action being executed
  #   - +study+ (Study) => parent study of file
  #   - +study_file+ (StudyFile) => File to be ingested/processed
  #   - +user+ (User) => user requesting action
  #   - +params_object+ (Multiple) => Job parameters object, e.g. ImagePipelineParameters
  #   - +boot_disk_size_gb+ (Integer) => size of boot disk, in GB
  #
  # * *returns*
  #   - (Hash)
  def job_labels(action:, study:, study_file:, user:, params_object:, boot_disk_size_gb: 300)
    ingest_attributes = AdminConfiguration.get_ingest_docker_image_attributes
    docker_image = ingest_attributes[:image_name]
    docker_tag = ingest_attributes[:tag]
    machine_type = params_object.respond_to?(:machine_type) ? params_object&.machine_type : DEFAULT_MACHINE_TYPE
    if params_object && params_object.respond_to?(:docker_image)
      image_attributes = params_object.docker_image.split('/').last
      docker_image, docker_tag = image_attributes.split(':')
    end
    {
      study_accession: sanitize_label(study.accession),
      user_id: user.id.to_s,
      filename: sanitize_label(study_file.upload_file_name),
      action: label_for_action(action),
      docker_image: sanitize_label(docker_image),
      docker_tag: sanitize_label(docker_tag),
      environment: Rails.env.to_s,
      file_type: sanitize_label(study_file.file_type),
      machine_type: machine_type,
      boot_disk_size_gb: sanitize_label(boot_disk_size_gb)
    }
  end

  # shorthand label for action
  #
  # * *params*
  #   - +action+ (String) => original action
  #
  # * *returns*
  #   - (String) => label for action, condensing all ingest actions to 'ingest'
  def label_for_action(action)
    case action.to_s
    when /ingest/
      'ingest_pipeline'
    when /differential/
      'differential_expression'
    when 'render_expression_arrays'
      'data_cache_pipeline'
    else
      action
    end
  end

  # sanitizer for GCE label value (lowercase, alphanumeric with dash & underscore only, 63 characters)
  # see https://cloud.google.com/compute/docs/labeling-resources#requirements for more info
  #
  # * *params*
  #   - +label+ (String, Symbol, Integer) => label value
  #
  # * *returns*
  #   - (String) => lowercase label with invalid characters removed
  def sanitize_label(label)
    label.to_s.gsub(LABEL_SANITIZER, '_').downcase[0...63]
  end

  private

  # Validate ingest action against file type
  #
  # * *params*
  #   - +action+ (String/Symbol) => Ingest action to perform
  #   - +study_file+ (StudyFile) => File to be ingested
  #
  # * *raises*
  #   - (ArgumentError) => Ingest action & StudyFile do not correspond with each other, or StudyFile is not parseable
  def validate_action_by_file(action, study_file)
    if !study_file.able_to_parse?
      raise ArgumentError.new("'#{study_file.upload_file_name}' is not parseable or missing required bundled files")
    elsif !FILE_TYPES_BY_ACTION[action.to_sym].include?(study_file.file_type)
      raise ArgumentError.new("'#{action}' cannot be run with file type '#{study_file.file_type}'")
    end
  end

  # Escape double-quotes in JSON to pass to Python
  #
  # * *params*
  #   - +json+ (JSON) => JSON object
  #
  # * *returns*
  #   - (JSON) => Sanitized JSON object with escaped double quotes
  def sanitize_json(json)
    json.gsub("\"", "'")
  end

  # helper to determine which actions need custom GCP vms
  #
  # * *params*
  #   - +action_name+ (String, Symbol) => name of action to run, from IngestJob::VALID_ACTIONS
  def needs_custom_vm?(action_name)
    CUSTOM_VM_ACTIONS.include?(action_name.to_sym)
  end

  # determine if an external parameters object is valid (e.g. DifferentialExpressionParameters)
  # must validate internally and also implement Parameterizable#to_options_array
  def params_object_valid?(params_object)
    params_object.valid? && params_object.respond_to?(:to_options_array)
  end
end
