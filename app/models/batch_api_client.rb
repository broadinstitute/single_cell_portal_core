# frozen_string_literal: true
#
# Wrapper around Google Batch API for submitting for submitting/reporting scp-ingest-service jobs
class BatchApiClient
  extend ServiceAccountManager

  attr_accessor :project, :service_account_credentials, :service

  # Google authentication scopes necessary for running pipelines
  GOOGLE_SCOPES = %w(https://www.googleapis.com/auth/cloud-platform)

  # Network and sub-network names, if needed
  GCP_NETWORK_NAME = ENV['GCP_NETWORK_NAME']
  GCP_SUB_NETWORK_NAME = ENV['GCP_SUB_NETWORK_NAME']

  # List of scp-ingest-pipeline actions and their allowed file types
  FILE_TYPES_BY_ACTION = {
    ingest_expression: ['Expression Matrix', 'MM Coordinate Matrix', 'AnnData'],
    ingest_cluster: %w[Cluster AnnData],
    ingest_cell_metadata: %w[Metadata AnnData],
    ingest_subsample: %w[Cluster AnnData],
    differential_expression: %w[Cluster AnnData],
    ingest_differential_expression: ['Differential Expression'],
    render_expression_arrays: %w[Cluster],
    image_pipeline: %w[Cluster],
    ingest_anndata: %w[AnnData]
  }.freeze

  # default GCE machine_type
  DEFAULT_MACHINE_TYPE = 'n2d-highmem-4'.freeze

  # default compute region
  DEFAULT_COMPUTE_REGION = 'us-central1'

  # regex to sanitize label values for VMs/pipelines
  # alphanumeric plus - and _
  LABEL_SANITIZER = /[^a-zA-Z\d\-_]/

  # Enums for handling jobs
  COMPLETED_STATES = %w(SUCCEEDED FAILED DELETION_IN_PROGRESS)
  RUNNING_STATES = %w(STATE_UNSPECIFIED QUEUED SCHEDULED RUNNING)

  # Default constructor for BatchApiClient
  #
  # * *params*
  #   - +project+: (String) => GCP Project number to use (can be overridden by other parameters)
  #   - +service_account_credentials+: (Path) => Absolute filepath to service account credentials
  # * *return*
  #   - +BatchApiClient+
  def initialize(project = self.class.compute_project, service_account_credentials = self.class.get_primary_keyfile)
    credentials = {
      scope: GOOGLE_SCOPES,
      json_key_io: File.open(service_account_credentials)
    }

    authorizer = Google::Auth::ServiceAccountCredentials.make_creds(credentials)
    batch_service = Google::Apis::BatchV1::BatchService.new
    batch_service.authorization = authorizer

    self.project = project
    self.service_account_credentials = service_account_credentials
    self.service = batch_service
  end

  # Return the service account email
  #
  # * *return*
  #   - (String) Service Account email
  def issuer
    service.authorization.issuer
  end

  # the project and location that all requests should be executed against
  #
  # * *return*
  #   - (String) the GCP project number and default compute region
  def project_location
    "projects/#{project}/locations/#{DEFAULT_COMPUTE_REGION}"
  end

  # Returns a list of all pipelines run in this project
  # Note: the 'filter' parameter is broken for this method and is not supported here
  #
  # * *params*
  #   - +page_token+ (String) => Request next page of results using token
  #
  # * *return*
  #   - (Google::Apis::BatchV1::ListJobsResponse)
  #
  # * *raises*
  #   - (Google::Apis::ServerError) => An error occurred on the server and the request can be retried
  #   - (Google::Apis::ClientError) =>  The request is invalid and should not be retried without modification
  #   - (Google::Apis::AuthorizationError) => Authorization is required
  def list_jobs(page_token: nil)
    service.list_project_location_jobs(project_location, page_token:)
  end

  # main handler to create and run a Batch API job
  #
  # * *params*
  #   - +study_file+ (StudyFile) => File to be ingested
  #   - +user+ (User) => User performing ingest action
  #   - +action+ (String) => Action that is being performed, maps to Ingest pipeline action
  #     (e.g. 'ingest_cell_metadata', 'subsample')
  #   - +params_object+ (Class) => Class containing parameters for Batch job (like DifferentialExpressionParameters)
  #                                must include Parameterizable concern for to_options_array support
  #
  # * *returns*
  #   - (Google::Apis::BatchV1::Job)
  #
  # * *raises*
  #   - [Google::Apis::ServerError] An error occurred on the server and the request can be retried
  #   - [Google::Apis::ClientError] The request is invalid and should not be retried without modification
  #   - [Google::Apis::AuthorizationError] Authorization is required
  def run_job(study_file:, user:, action:, params_object: nil)
    study = study_file.study
    labels = job_labels(action:, study:, study_file:, user:, params_object:)
    machine_type = job_machine_type(params_object)
    instance_policy = create_instance_policy(machine_type:)
    allocation_policy = create_allocation_policy(instance_policy:, labels:)
    container = create_container(study_file:, user_metrics_uuid: user.metrics_uuid, action:, params_object:)
    task_group = create_task_group(action:, machine_type:, container:, labels: {})
    job = create_job(task_group:, allocation_policy:, labels:)
    Rails.logger.info "Request object sent to Google Batch API, excluding 'environment' parameters:"
    Rails.logger.info log_params(job).to_yaml
    service.create_project_location_job(project_location, job, quota_user: user.id.to_s)
  end

  # create a job object to pass to a request
  #
  # * *params*
  #   - +task_group+ (Google::Apis::BatchV1::TaskGroup)
  #   - +allocation_policy+ (Google::Apis::BatchV1::AllocationPolicy)
  #   - +labels+ (Hash) => labels to apply to job and all compute resources
  #
  # * *returns*
  #   - (Google::Apis::BatchV1::Job)
  def create_job(task_group:, allocation_policy:, labels: {})
    Google::Apis::BatchV1::Job.new(
      task_groups: [task_group],
      allocation_policy:,
      labels:,
      logs_policy: Google::Apis::BatchV1::LogsPolicy.new(destination: 'CLOUD_LOGGING')
    )
  end

  # Get an existing batch job
  #
  # * *params*
  #   - +name+ () => Name of existing Batch API job
  #   - +fields+ (String) => Selector specifying which fields to include in a partial response.
  #   - +user+ (User) => User that originally submitted pipeline
  #
  # * *return*
  #   - (Google::Apis::BatchV1::Job)
  def get_job(name, fields: nil, user: nil)
    service.get_project_location_job(name, fields:, quota_user: user&.id.to_s)
  end

  # helper to determine if a job is done
  #
  # * *params*
  #   - +job+ (Google::Apis::BatchV1::Job) => Batch job object (optional)
  #
  # * *returns*
  #   - (Boolean)
  def job_done?(job)
    COMPLETED_STATES.include?(job.status.state)
  end

  # Get the task from an existing batch job
  # This contains more status/error information that job status object itself
  #
  # * *params*
  #   - +name+ () => Name of existing Batch API job
  #   - +fields+ (String) => Selector specifying which fields to include in a partial response.
  #   - +user+ (User) => User that originally submitted pipeline
  #
  # * *return*
  #   - (Google::Apis::BatchV1::Task)
  def get_job_task(name, fields: nil, user: nil)
    task_name = "#{name}/taskGroups/group0/tasks/0" # only ever 1 task group with 1 task
    service.get_project_location_job_task_group_task(task_name, fields:, quota_user: user&.id.to_s)
  end

  # retrieve an exit code directly from a task object
  #
  # * *params*
  #   - +name+ () => Name of existing Batch API job
  #
  # * *returns*
  #   - (Integer or Nil::NilClass)
  def exit_code_from_task(name)
    task = get_job_task(name)
    task.status.status_events.each do |event|
      code = event.task_execution&.exit_code
      return code.to_i if code
    end
    nil
  end

  # extract an error from the task object
  #
  # * *params*
  #   - +name+ () => Name of existing Batch API job
  #
  # * *returns*
  #   - (Google::Apis::BatchV1::TaskStatus or Nil::NilClass)
  def job_error(name)
    task = get_job_task(name)
    task.status.status_events.detect { |event| event.task_state == 'FAILED' }
  end

  # get a task specification from either a job, or look up by job name
  # TaskSpec objects contain information about compute resources/environment and Docker container
  #
  # * *params*
  #   - +name+ () => Name of existing Batch API job (optional)
  #   - +job+ (Google::Apis::BatchV1::Job) => Batch job object (optional)
  #
  # * *return*
  #   - (Google::Apis::BatchV1::TaskSpec)
  def get_job_task_spec(name: nil, job: nil)
    batch_job = job || get_job(name)
    batch_job.task_groups.first.task_spec
  end

  # get the command line from the Docker container in the Batch job
  #
  # * *params*
  #   - +name+ () => Name of existing Batch API job (optional)
  #   - +job+ (Google::Apis::BatchV1::Job) => Batch job object (optional)
  #
  # * *return*
  #   - (Array<String>) => CLI arguments as array
  def get_job_command_line(name: nil, job: nil)
    get_job_task_spec(name:, job:).runnables.first.container.commands
  end

  # get resource information about a Batch job
  #
  # * *params*
  #   - +name+ () => Name of existing Batch API job (optional)
  #   - +job+ (Google::Apis::BatchV1::Job) => Batch job object (optional)
  #
  # * *returns*
  #   - (Hash) => vm information (machine_type, disk size) and task allocations (cpu_milli & memory)
  def get_job_resources(name: nil, job: nil)
    batch_job = job || get_job(name)
    task_spec = get_job_task_spec(job: batch_job)
    compute = task_spec.compute_resource
    vm_info = batch_job.allocation_policy.instances.first.policy
    {
      cpu_milli: compute.cpu_milli,
      memory_mib: compute.memory_mib,
      machine_type: vm_info.machine_type,
      boot_disk_size_gb: vm_info.boot_disk.size_gb
    }
  end

  # get loggable parameters for reporting
  #
  # * *params*
  #   - +job+ (Google::Apis::BatchV1::Job)
  #
  # * *returns*
  #   - (Hash) => metadata about job run, including command line and VM stats
  def log_params(job)
    commands = get_job_command_line(job:)
    vm_instance = get_job_resources(job:)
    {
      task: {
        commands:,
        resources: {
          regions: DEFAULT_COMPUTE_REGION,
          labels: job.allocation_policy.labels,
          virtual_machine: {
            boot_disk_size_gb: vm_instance[:boot_disk_size_gb],
            machine_type: vm_instance[:machine_type]
          },
          service_account: issuer,
          network: GCP_NETWORK_NAME
        }
      }
    }
  end

  # create a task group that represents entire Batch job
  # includes GCE resources, environment, Docker info, etc.
  #
  # * *params*
  #   - +action+ (String/Symbol) => Action to perform on ingest
  #   - +machine_type+ (String) => GCP VM machine type (defaults to 'n2d-highmem-4': 4 CPU, 32GB RAM)
  #   - +container+ (Google::Apis::BatchV1::Container)
  #   - +labels+ (Hash) => labels to apply to job and all compute resources
  #
  # * *returns*
  #   - (Google::Apis::BatchV1::TaskGroup)
  def create_task_group(action:, machine_type:, container:, labels: {})
    runnable = Google::Apis::BatchV1::Runnable.new(
      container:,
      environment: Google::Apis::BatchV1::Environment.new(
        variables: set_environment_variables(action:)
      ),
      labels:
    )
    task = Google::Apis::BatchV1::TaskSpec.new(
      max_retry_count: 0,
      runnables: [runnable],
      compute_resource: create_compute_resource(machine_type)
    )
    Google::Apis::BatchV1::TaskGroup.new(
      task_count: 1,
      task_spec: task
    )
  end

  # configure associated Docker container that runs inside job
  #
  # * *params*
  #   - +study_file+ (StudyFile) => StudyFile to be ingested
  #   - +action+ (String/Symbol) => Action to perform on ingest
  #   - +params_object+ (Class) => Class containing parameters for Batch job (like DifferentialExpressionParameters)
  #                                must implement :to_options_array method
  #
  # * *returns*
  #   - (Google::Apis::BatchV1::Container)
  def create_container(study_file:, action:, user_metrics_uuid:, params_object: nil)
    Google::Apis::BatchV1::Container.new(
      commands: format_command_line(study_file:, action:, user_metrics_uuid:, params_object:),
      image_uri: image_uri_for_job(params_object)
    )
  end

  # set which Docker image to pull
  #
  # * *params*
  #   - +params_object+ (Class) => Class containing parameters for Batch job (like DifferentialExpressionParameters)
  #
  # * *returns*
  #   - (String) Docker image URI
  def image_uri_for_job(params_object)
    if params_object && params_object.respond_to?(:docker_image)
      params_object.docker_image
    else
      AdminConfiguration.get_ingest_docker_image
    end
  end

  # create a compute resource for a task spec
  # this will ensure that all available CPU/RAM are utilized for each task
  # see https://cloud.google.com/batch/docs/reference/rest/v1/projects.locations.jobs#ComputeResource for more info
  #
  # * *params*
  #   - +machine_type+ (String) => GCP VM machine type (defaults to 'n2d-highmem-4': 4 CPU, 32GB RAM)
  #
  # * *returns*
  #   - (Google::Apis::BatchV1::ComputeResource)
  def create_compute_resource(machine_type)
    cores = machine_type.split('-').last.to_i
    Google::Apis::BatchV1::ComputeResource.new(
      cpu_milli: cores * 1000, memory_mib: cores * 8 * 1024
    )
  end

  # create an allocation policy to manage all instances in a job
  #
  # * *params*
  #   - +instance_policy+ (Google::Apis::BatchV1::InstancePolicy)
  #   - +labels+ (Hash) => labels to apply to job and all compute resources
  #
  # * *returns*
  #   - (Google::Apis::BatchV1::AllocationPolicy)
  def create_allocation_policy(instance_policy:, labels: {})
    instances = Google::Apis::BatchV1::InstancePolicyOrTemplate.new(
      policy: instance_policy,
      location: Google::Apis::BatchV1::LocationPolicy.new(
        allowed_locations: ["regions/#{DEFAULT_COMPUTE_REGION}"]
      )
    )
    Google::Apis::BatchV1::AllocationPolicy.new(
      labels:,
      instances: [instances],
      network: Google::Apis::BatchV1::NetworkPolicy.new(
        network_interfaces: [
          Google::Apis::BatchV1::NetworkInterface.new(
            network: "projects/#{project}/global/networks/#{GCP_NETWORK_NAME}",
            subnetwork: "projects/#{project}/regions/#{DEFAULT_COMPUTE_REGION}/subnetworks/#{GCP_SUB_NETWORK_NAME}")
        ]
      ),
      service_account: Google::Apis::BatchV1::ServiceAccount.new(email: issuer, scopes: GOOGLE_SCOPES)
    )
  end

  # create an instance policy that defines what types of VMs to create for this batch job
  #
  # * *params*
  #   - +machine_type+ (String) => GCP VM machine type (defaults to 'n2d-highmem-4': 4 CPU, 32GB RAM)
  #   - +boot_disk_size_gb+ (Integer) => Size of boot disk for VM, in gigabytes (defaults to 100GB)
  #
  # * *return*
  #   - (Google::Apis::BatchV1::InstancePolicy)
  def create_instance_policy(machine_type: DEFAULT_MACHINE_TYPE, boot_disk_size_gb: 300)
    Google::Apis::BatchV1::InstancePolicy.new(
      machine_type:,
      boot_disk: Google::Apis::BatchV1::Disk.new(size_gb: boot_disk_size_gb),
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
  def format_command_line(study_file:, action:, user_metrics_uuid:, params_object: nil)
    validate_action_by_file(action, study_file)
    study = study_file.study
    # Docker accepts command line in array form for better tokenization of parameters
    command_line = [
      'python', 'ingest_pipeline.py', '--study-id', study.id.to_s, '--study-file-id', study_file.id.to_s,
      '--user-metrics-uuid', user_metrics_uuid, action.to_s
    ]
    action_cli_opt = Parameterizable.to_cli_opt(action)
    case action.to_s
    when 'ingest_expression'
      case study_file.file_type
      when 'Expression Matrix'
        command_line += ['--matrix-file', study_file.gs_url, '--matrix-file-type', 'dense']
      when 'MM Coordinate Matrix'
        bundled_files = study_file.bundled_files
        genes_file = bundled_files.detect { |f| f.file_type == '10X Genes File' }
        barcodes_file = bundled_files.detect { |f| f.file_type == '10X Barcodes File' }
        command_line += [
          '--matrix-file', study_file.gs_url, '--matrix-file-type', 'mtx', '--gene-file', genes_file.gs_url,
          '--barcode-file', barcodes_file.gs_url
        ]
      end
    when 'ingest_cell_metadata'
      # skip if parent file is AnnData as params_object will format command line
      unless study_file.is_anndata?
        command_line += [
          '--cell-metadata-file', study_file.gs_url, '--study-accession', study.accession, action_cli_opt
        ]
      end
      if study_file.use_metadata_convention
        command_line += [
          '--validate-convention', '--bq-dataset', CellMetadatum::BIGQUERY_DATASET,
          '--bq-table', CellMetadatum::BIGQUERY_TABLE
        ]
      end
    when 'ingest_cluster'
      # skip if parent file is AnnData as params_object will format command line
      command_line += ['--cluster-file', study_file.gs_url, action_cli_opt] unless study_file.is_anndata?
    when 'ingest_subsample'
      unless study_file.is_anndata?
        metadata_file = study.metadata_file
        command_line += ['--cluster-file', study_file.gs_url, '--cell-metadata-file', metadata_file.gs_url, '--subsample']
      end
    when 'differential_expression'
      command_line += ['--study-accession', study.accession]
    when 'ingest_differential_expression'
      de_info = study_file.differential_expression_file_info
      command_line += [
        '--annotation-name', de_info.annotation_name, '--annotation-scope', de_info.annotation_scope,
        '--annotation-type', 'group', '--cluster-name', de_info.cluster_group.name,
        '--gene-header', de_info.gene_header, '--group-header', de_info.group_header, '--comparison-group-header', de_info.comparison_group_header,
        '--size-metric', de_info.size_metric, '--significance-metric', de_info.significance_metric,
        '--differential-expression-file', study_file.gs_url, '--study-accession', study.accession,
        '--method', de_info.computational_method, action_cli_opt
      ]
    when 'image_pipeline'
      # image_pipeline is node-based, so python command line to this point no longer applies
      command_line = %w[node expression-scatter-plots.js]
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
    command_line + optional_args
  end

  # Assemble any optional command line options for ingest by file type
  #
  # * *params*
  #   - +study_file+ (StudyFile) => File to be ingested
  #   - +action+ (String/Symbol) => Action being performed on file
  #
  # * *returns*
  #   - (Array) => Array representation of optional arguments (Docker exec form), based on file type
  def get_command_line_options(study_file, action)
    opts = []
    case study_file.file_type
    when /Matrix/
      if study_file.taxon.present?
        taxon = study_file.taxon
        opts += [
          '--taxon-name', taxon.scientific_name, '--taxon-common-name', taxon.common_name,
          '--ncbi-taxid', taxon.ncbi_taxid.to_s
        ]
      end
    when 'Cluster'
      # the name of Cluster files is the same as the name of the cluster object itself
      opts += ['--name', study_file.name]
      # add domain ranges if this cluster is being ingested (not needed for subsampling)
      if action.to_sym == :ingest_cluster
        if study_file.get_cluster_domain_ranges.any?
          opts += ['--domain-ranges', sanitize_json(study_file.get_cluster_domain_ranges.to_json).to_s]
        else
          opts += %w[--domain-ranges {}]
        end
      end
    end
    opts
  end

  # get the machine type for this Batch job
  #
  # * *params*
  #   - +params_object+ (Multiple) => Job parameters object, e.g. ImagePipelineParameters
  #
  # * *returns*
  #   - (String) => GCE machine type, e.g. n2d-highmem-4
  def job_machine_type(params_object = nil)
    params_object.respond_to?(:machine_type) ? params_object&.machine_type : DEFAULT_MACHINE_TYPE
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
    if params_object && params_object.respond_to?(:docker_image)
      image_attributes = params_object.docker_image.split('/').last
      docker_image, docker_tag = image_attributes.split(':')
    end
    {
      study_accession: sanitize_label(study.accession),
      user_id: user.id.to_s,
      filename: sanitize_label(study_file.upload_file_name),
      action: label_for_action(action),
      ingest_action: action,
      docker_image: sanitize_label(docker_image),
      docker_tag: sanitize_label(docker_tag),
      environment: Rails.env.to_s,
      file_type: sanitize_label(study_file.file_type),
      machine_type: job_machine_type(params_object),
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

  # pull out actionable info from error HTTP response
  #
  # * *params*
  #   - +error+ (Google::Apis::Error) => error object
  #
  # * *returns*
  #   - (String) => formatted error message
  def parse_error_message(error)
    if error.respond_to?(:body)
      error_contents = JSON.parse(error.body)['error']
      "#{error.message} (#{error_contents['code']}): #{error_contents['message']}"
    else
      "#{error.class}: #{error.message}"
    end
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

  # determine if an external parameters object is valid (e.g. DifferentialExpressionParameters)
  # must validate internally and also implement Parameterizable#to_options_array
  def params_object_valid?(params_object)
    params_object.valid? && params_object.respond_to?(:to_options_array)
  end
end
