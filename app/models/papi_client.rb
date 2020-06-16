require 'google/apis/genomics_v2alpha1'

##
# PapiClient: a lightweight wrapper around the Google Cloud Genomics V2 Alpha API for submitting/reporting
# scp-ingest-service jobs to ingest user-uploaded data to Firestore
#
# requires: googleauth, google-api-client, FireCloudClient class (for bucket access)
#
# Author::  Jon Bistline  (mailto:bistline@broadinstitute.org)

class PapiClient < Struct.new(:project, :service_account_credentials, :service)

  extend ErrorTracker

  # Service account JSON credentials
  SERVICE_ACCOUNT_KEY = !ENV['SERVICE_ACCOUNT_KEY'].blank? ? (ENV['NON_DOCKERIZED'] ? ENV['SERVICE_ACCOUNT_KEY'] : File.absolute_path(ENV['SERVICE_ACCOUNT_KEY'])) : ''
  # Google authentication scopes necessary for running pipelines
  GOOGLE_SCOPES = %w(https://www.googleapis.com/auth/cloud-platform)
  # GCP Compute project to run pipelines in
  COMPUTE_PROJECT = ENV['GOOGLE_CLOUD_PROJECT'].blank? ? '' : ENV['GOOGLE_CLOUD_PROJECT']
  # Docker image in GCP project to pull for running ingest jobs
  INGEST_DOCKER_IMAGE = 'gcr.io/broad-singlecellportal-staging/scp-ingest-pipeline:1.3.9'
  # Network and sub-network names, if needed
  GCP_NETWORK_NAME = ENV['GCP_NETWORK_NAME']
  GCP_SUB_NETWORK_NAME = ENV['GCP_SUB_NETWORK_NAME']
  # List of scp-ingest-pipeline actions and their allowed file types
  FILE_TYPES_BY_ACTION = {
      ingest_expression: ['Expression Matrix', 'MM Coordinate Matrix'],
      ingest_cluster: ['Cluster'],
      ingest_cell_metadata: ['Metadata'],
      ingest_subsample: ['Cluster']
  }

  # Default constructor for PapiClient
  #
  # * *params*
  #   - +project+: (String) => GCP Project to use (can be overridden by other parameters)
  #   - +project+: (Path) => Absolute filepath to service account credentials
  # * *return*
  #   - +PapiClient+
  def initialize(project=COMPUTE_PROJECT, service_account_credentials=SERVICE_ACCOUNT_KEY)

    credentials = {
        scope: GOOGLE_SCOPES
    }

    if SERVICE_ACCOUNT_KEY.present?
      credentials.merge!({json_key_io: File.open(service_account_credentials)})
    end

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
    self.service.authorization.issuer
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
    self.service.list_project_operations("projects/#{COMPUTE_PROJECT}/operations", page_token: page_token)
  end

  # Runs a pipeline.  Will call sub-methods to instantiate required objects to pass to
  # Google::Apis::GenomicsV2alpha1::GenomicsService.run_pipeline
  #
  # * *params*
  #   - +study_file+ (StudyFile) => File to be ingested
  #   - +user+ (User) => User performing ingest action
  #   - +action+ (String) => Action that is being performed, maps to Ingest pipeline action
  #     (e.g. 'ingest_cell_metadata', 'subsample')
  #
  # * *return*
  #   - (Google::Apis::GenomicsV2alpha1::Operation)
  #
  # * *raises*
  #   - (Google::Apis::ServerError) => An error occurred on the server and the request can be retried
  #   - (Google::Apis::ClientError) =>  The request is invalid and should not be retried without modification
  #   - (Google::Apis::AuthorizationError) => Authorization is required
  def run_pipeline(study_file: , user:, action:)
    study = study_file.study
    accession = study.accession
    resources = self.create_resources_object(regions: ['us-central1'])
    command_line = self.get_command_line(study_file: study_file, action: action)
    labels = {
        study_accession: accession,
        user_id: user.id.to_s,
        file_id: study_file.id.to_s,
        action: action,
        docker_image: INGEST_DOCKER_IMAGE
    }
    environment = self.set_environment_variables
    action = self.create_actions_object(commands: command_line, environment: environment)
    pipeline = self.create_pipeline_object(actions: [action], environment: environment, resources: resources)
    pipeline_request = self.create_run_pipeline_request_object(pipeline: pipeline, labels: labels)
    Rails.logger.info "Request object sent to Google Pipelines API (PAPI), excluding 'environment' parameters:"
    sanitized_pipeline_request = pipeline_request.to_h[:pipeline].except(:environment)
    sanitized_pipeline_request[:actions] = sanitized_pipeline_request[:actions][0].except(:environment)
    Rails.logger.info sanitized_pipeline_request.to_yaml
    self.service.run_pipeline(pipeline_request, quota_user: user.id.to_s)
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
  def get_pipeline(name: , fields: nil, user: nil)
    quota_user = user.present? ? user.id.to_s : nil
    self.service.get_project_operation(name, fields: fields, quota_user: quota_user)
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
    Google::Apis::GenomicsV2alpha1::RunPipelineRequest.new(
        pipeline: pipeline,
        labels: labels
    )
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
    Google::Apis::GenomicsV2alpha1::Pipeline.new(
        actions: actions,
        environment: environment,
        resources: resources,
        timeout: timeout
    )
  end

  # Instantiate actions for pipeline, which holds command line actions, docker information,
  # and information that is passed to run_pipeline.  The Docker image that is pulled for this
  # is hard-coded to PapiClient::INGEST_DOCKER_IMAGE
  #
  # * *params*
  #   - +commands+: (Array<String>) => An array of commands to run inside the container
  #   - +environment+: (Hash) => Hash of key/value pairs to set as the container env
  #   - +flags+: (Array<String>) => An array of flags to apply to the action
  #   - +image_uri+: (String) => GCR Docker image to pull, defaults to PapiClient::INGEST_DOCKER_IMAGE
  #   - +labels+: (Hash) => Hash of labels to associate with the action
  #   - +timeout+: (String) => Maximum runtime of action
  #
  #  * *return*
  #   - (Google::Apis::GenomicsV2alpha1::Action)
  def create_actions_object(commands: [], environment: {}, flags: [], labels: {}, timeout: nil)
    Google::Apis::GenomicsV2alpha1::Action.new(
        commands: commands,
        environment: environment,
        flags: flags,
        image_uri: INGEST_DOCKER_IMAGE,
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
  #
  # * *returns*
  #   - (Hash) => Hash of required environment variables
  def set_environment_variables
    {
        'DATABASE_HOST' => ENV['MONGO_INTERNAL_IP'],
        'MONGODB_USERNAME' => 'single_cell',
        'MONGODB_PASSWORD' => ENV['PROD_DATABASE_PASSWORD'],
        'DATABASE_NAME' => Mongoid::Config.clients["default"]["database"],
        'GOOGLE_PROJECT_ID' => COMPUTE_PROJECT
    }
  end

  # Instantiate a resources object to tell where to run a pipeline
  #
  # * *params*
  #   - regions: (Array<String>) => An array of GCP regions allowed for VM allocation
  #
  # * *return*
  #   - (Google::Apis::GenomicsV2alpha1::Resources)
  def create_resources_object(regions:)
    Google::Apis::GenomicsV2alpha1::Resources.new(
         project_id: COMPUTE_PROJECT,
         regions: regions,
         virtual_machine: self.create_virtual_machine_object
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
  # * *return*
  #   - (Google::Apis::GenomicsV2alpha1::VirtualMachine)
  def create_virtual_machine_object(machine_type: 'n1-highmem-4', boot_disk_size_gb: 100, preemptible: false)
    virtual_machine = Google::Apis::GenomicsV2alpha1::VirtualMachine.new(
        machine_type: machine_type,
        preemptible: preemptible,
        boot_disk_size_gb: boot_disk_size_gb,
        service_account: Google::Apis::GenomicsV2alpha1::ServiceAccount.new(email: self.issuer, scopes: GOOGLE_SCOPES)
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
  #
  # * *return*
  #   - (Array) Command Line, in Docker "exec" format
  #
  # * *raises*
  #   - (ArgumentError) => The requested StudyFile and action do not correspond with each other, or cannot be run yet
  def get_command_line(study_file:, action:)
    validate_action_by_file(action, study_file)
    study = study_file.study
    command_line = "python ingest_pipeline.py --study-id #{study.id} --study-file-id #{study_file.id} #{action}"
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
      command_line += " --cell-metadata-file #{study_file.gs_url} --study-accession #{study.accession} --ingest-cell-metadata"
      if study_file.use_metadata_convention
        command_line += " --validate-convention --bq-dataset #{CellMetadatum::BIGQUERY_DATASET} --bq-table #{CellMetadatum::BIGQUERY_TABLE}"
      end
    when 'ingest_cluster'
      command_line += " --cluster-file #{study_file.gs_url} --ingest-cluster"
    when 'ingest_subsample'
      metadata_file = study.metadata_file
      command_line += " --cluster-file #{study_file.gs_url} --cell-metadata-file #{metadata_file.gs_url} --subsample"
    end

    # add optional command line arguments based on file type
    optional_args = self.get_command_line_options(study_file, action)
    # return an array of tokens (Docker expects exec form, which runs without a shell, so cannot be a single command)
    exec_form = command_line.split + optional_args
    exec_form
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
        if taxon.current_assembly.present?
          assembly = taxon.current_assembly
          opts += ["--genome-assembly-accession", "#{assembly.accession}"]
          if assembly.current_annotation.present?
            opts += ["--genome-annotation", "#{assembly.current_annotation.name}"]
          end
        end
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
end
