##
#
# Human Cell Atlas formatted metadata relating to analyses
# https://github.com/HumanCellAtlas/metadata-schema/blob/master/json_schema/analysis.json
#
##

class AnalysisMetadatum
  include Mongoid::Document
  include Mongoid::Timestamps
  extend ErrorTracker

  # field definitions
  belongs_to :study, optional: true
  field :payload, type: Hash # actual HCA JSON payload
  field :version, type: String # string version number indicating an HCA release
  field :name, type: String
  field :submission_id, type: String # FireCloud submission ID, also used as internal analysis_id
  field :submitter, type: String # user that submitted the analysis

  ##
  # INDEXES
  ##

  index({ study_id: 1, submission_id: 1}, { unique: true })

  ##
  # VALIDATIONS
  ##

  validates_presence_of :payload, :version, :name, :submission_id
  validates_uniqueness_of :submission_id

  ##
  # CALLBACKS
  ##

  before_validation :set_payload, on: :create

  ##
  # CONSTANTS
  ##

  # the following constants are hashes of metadata versions with ordered lists of field names to allow mapping
  # to and from HCA- & FireCloud-style names
  HCA_TASK_INFO = {
      '4.6.1' => %w(cpus disk_size docker_image log_err log_out memory name start_time stop_time zone)
  }
  FIRECLOUD_TASK_INFO = {
      '4.6.1' => %w(runtimeAttributes/cpu runtimeAttributes/disks runtimeAttributes/docker stderr stdout runtimeAttributes/memory name start end runtimeAttributes/zones)
  }

  ##
  # INSTANCE METHODS
  ##

  # helper method to return just the analysis namespace/name/snapshot for a FireCloud method
  def analysis_method_name
    method = self.payload['computational_method']
    method.present? ? method.gsub(/https:\/\/api\.firecloud\.org\/api\/methods\//, '') : ''
  end

  # root directory for storing metadata schema copies
  def definition_root
    Rails.root.join('data', 'HCA_metadata', self.version)
  end

  # remote endpoint containing metadata schema
  def definition_url
    "https://raw.githubusercontent.com/HumanCellAtlas/metadata-schema/#{self.version}/json_schema/analysis.json"
  end

  # local filesytem location of copy of JSON schema
  def definition_filepath
    Rails.root.join(self.definition_root, 'analysis.json')
  end

  # return a parsed JSON object detailing the metadata schema for this object
  def definition_schema
    begin
      # check for local copy first
      if File.exists?(self.definition_filepath)
        existing_schema = File.read(self.definition_filepath)
        JSON.parse(existing_schema)
      else
        Rails.logger.info "#{Time.zone.now}: saving new local copy of #{self.definition_filepath}"
        metadata_schema = RestClient.get self.definition_url
        # write a local copy
        unless Dir.exist?(self.definition_root)
          FileUtils.mkdir_p(self.definition_root)
        end
        new_schema = File.new(self.definition_filepath, 'w+')
        new_schema.write metadata_schema.body
        new_schema.close
        JSON.parse(metadata_schema.body)
      end
    rescue RestClient::ExceptionWithResponse => e
      ErrorTracker.report_exception(e, self.study.user, {request_url: self.definition_url, request_response: e.http_body})
      Rails.logger.error "#{Time.zone.now}: Error retrieving remote HCA Analysis metadata schema: #{e.message}"
      {error: "Error retrieving definition schema: #{e.message}"}
    rescue JSON::ParserError => e
      ErrorTracker.report_exception(e, self.study.user, {metadata_body: metadata_schema.body})
      Rails.logger.error "#{Time.zone.now}: Error parsing HCA Analysis metadata schema: #{e.message}"
      {error: "Error parsing definition schema: #{e.message}"}
    end
  end

  # retrieve property or nested field definition information
  # can retrieve info such as require fields, field definitions, property list, etc.
  def definitions(key, field=nil)
    begin
      defs = self.definition_schema[key]
      if field.present?
        defs[field]
      else
        defs
      end
    rescue NoMethodError => e
      field_key = field.present? ? "#{key}/#{field}" : key
      ErrorTracker.report_exception(e, self.study.user, {missing_key: field_key, analysis_metadatum: self.attributes.to_h})
      Rails.logger.error "#{Time.zone.now}: Error accessing remote HCA Analysis metadata field definitions for #{field_key}: #{e.message}"
      nil
    end
  end

  # retrieve a mapping of field names between HCA task metadata and FireCloud call metadata
  def task_mapping(type='HCA')
    case type
      when 'HCA'
        Hash[AnalysisMetadatum::HCA_TASK_INFO[self.version].zip(AnalysisMetadatum::FIRECLOUD_TASK_INFO[self.version])]
      when 'FireCloud'
        Hash[AnalysisMetadatum::FIRECLOUD_TASK_INFO[self.version].zip(AnalysisMetadatum::HCA_TASK_INFO[self.version])]
      else
        nil
    end
  end

  # set a value based on the schema definition for a particular field
  def set_value_by_type(definitions, value)
    value_type = definitions['type']
    if value.present?
      case value_type
      when 'string'
        value.gsub(/\"/, '')
      when 'integer'
        value.to_i
      when 'array'
        if value.is_a?(Array)
          value
        elsif value.is_a?(String)
          # try to split on commas to convert into array
          value.split(',')
        end
      else
        value
      end
    end
  end

  # extract call-level metadata from a FireCloud submission to populate task attributes for an analysis
  def get_workflow_call_attributes(workflows)
    begin
      call_metadata = []
      workflows.each do |workflow|
        Rails.logger.info "#{Time.zone.now}: processing #{workflow['workflowName']} metadata for submission #{self.submission_id}"
        # for each 'call', extract the available information as defined by the 'task' definition for this
        # version of the analysis metadata schema
        workflow['calls'].each do |task, task_attributes|
          Rails.logger.info "#{Time.zone.now}: processing #{task} call metadata for submission #{self.submission_id}"
          call = {
              'name' => task
          }
          # task_attributes is an array of tasks with only one entry
          attributes = task_attributes.first
          # get available definitions and then load the corresponding value in FireCloud call metadata
          # using the HCA_TASK_MAP constant
          self.definitions('definitions','task')['properties'].each do |property, definitions|
            location = self.task_mapping[property]
            # only retrieve value if we have a valid map
            if location.present?
              # some fields are nested, so check first. do a conditional assignment in case we already have a value
              if location.include?('/')
                parent, child = location.split('/')
                call[property] ||= set_value_by_type(definitions, attributes.dig(parent, child))
              else
                call[property] ||= set_value_by_type(definitions, attributes[location])
              end
              # make sure we have a valid value type
            else
              # try to do a straight mapping, will likely miss
              Rails.logger.info "#{Time.zone.now}: trying unmappable HCA analysis.task property: #{property}"
              call[property] ||= set_value_by_type(definitions, attributes[property])
              next
            end
          end
          call_metadata << call
        end
      end
      call_metadata
    rescue => e
      ErrorTracker.report_exception(e, self.study.user, {workflows: workflows, analysis_metadatum: self.attributes.to_h})
      Rails.logger.error "#{Time.zone.now}: Error retrieving workflow call metadata for: #{e.message}"
      []
    end
  end

  # assemble payload object upon completion of a FireCloud submission
  def create_payload
    payload = {}
    study = self.study
    # retrieve available objects pertaining to submission (submission, configuration, all workflows contained in submission)
    Rails.logger.info "#{Time.zone.now}: creating AnalysisMetadatum payload for submission "
    submission = ApplicationController.firecloud_client.get_workspace_submission(study.firecloud_project,
                                                                 study.firecloud_workspace,
                                                                 self.submission_id)
    configuration = ApplicationController.firecloud_client.get_workspace_configuration(study.firecloud_project,
                                                                       study.firecloud_workspace,
                                                                       submission['methodConfigurationNamespace'],
                                                                       submission['methodConfigurationName'])
    analysis_configuration = AnalysisConfiguration.find_by(name: configuration['methodRepoMethod']['methodName'],
                                                           namespace: configuration['methodRepoMethod']['methodNamespace'],
                                                           snapshot: configuration['methodRepoMethod']['methodVersion'])
    workflows = []
    submission['workflows'].each do |submission_workflow|
      Rails.logger.info "getting workflow: #{submission_workflow['workflowId']}"

      workflows << ApplicationController.firecloud_client.get_workspace_submission_workflow(study.firecloud_project,
                                                                          study.firecloud_workspace,
                                                                          self.submission_id,
                                                                          submission_workflow['workflowId'])
    end
    # retrieve list of metadata properties
    properties = self.definitions('properties')
    properties.each do |property, definitions|
      # decide where to pull information based on the property requested
      value = nil
      case property
        when 'inputs'
          inputs = []
          workflows.each do |workflow|
            workflow['inputs'].each do |name, value|
              inputs << {'name' => name, 'value' => value}
            end
          end
          value = set_value_by_type(definitions, inputs)
        when 'reference_bundle'
          if analysis_configuration.present? && analysis_configuration.reference_bundle_name.present?
            value = set_value_by_type(definitions, configuration['inputs'][analysis_configuration.reference_bundle_name])
          else
            value = set_value_by_type(definitions, study.workspace_url)
          end
        when 'tasks'
          value = set_value_by_type(definitions, self.get_workflow_call_attributes(workflows))
        when 'description'
          method_name = configuration['methodRepoMethod']
          name = "#{method_name['methodNamespace']}/#{method_name['methodName']}/#{method_name['methodVersion']}"
          value = set_value_by_type(definitions, "Analysis submission of #{name} from Single Cell Portal")
        when 'timestamp_stop_utc'
          stop = nil
          workflows.each do |workflow|
            end_time = workflow['end']
            if stop.nil? || DateTime.parse(stop) > DateTime.parse(end_time)
              stop = end_time
            end
          end
          value = set_value_by_type(definitions, stop)
        when 'input_bundles'
          value = set_value_by_type(definitions, [study.workspace_url])
        when 'outputs'
          outputs = []
          workflows.each do |workflow|
            outs = workflow['outputs'].values
            outs&.each do |o|
              outputs << {
                  'name' => o.split('/').last,
                  'file_path' => o,
                  'format' => o.split('.').last
              }
            end
          end
          value = set_value_by_type(definitions, outputs)
        when 'name'
          value = set_value_by_type(definitions, configuration['name'])
        when 'computational_method'
          method_name = configuration['methodRepoMethod']
          name = "#{method_name['methodNamespace']}/#{method_name['methodName']}/#{method_name['methodVersion']}"
          method_url = ApplicationController.firecloud_client.api_root + "/api/methods/#{name}"
          value = set_value_by_type(definitions, method_url)
        when 'timestamp_start_utc'
          value = set_value_by_type(definitions, submission['submissionDate'])
        when 'core'
          core = {
              'type' => 'analysis',
              'schema_url' => self.definition_url,
              'schema_version' => self.version
          }
          value = set_value_by_type(definitions, core)
        when 'analysis_run_type'
          value = set_value_by_type(definitions, 'run')
        when 'metadata_schema'
          value = set_value_by_type(definitions, self.version)
        when 'analysis_id'
          value = set_value_by_type(definitions, self.submission_id)
      end
      payload[property] = value
    end
    payload
  end

  private

  # set payload object on create
  def set_payload
    self.payload = self.create_payload
  end
end
