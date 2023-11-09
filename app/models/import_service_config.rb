# base module for all ImportServiceConfig entities
module ImportServiceConfig
  extend ActiveSupport::Concern
  include ActiveModel::Model

  # allow word and space characters, plus the following: - . / ( ) , :
  ATTRIBUTE_SANITIZER = %r{[^\w\s\-./()+,:]}

  CONTENT_TYPES_BY_EXT = {
    'tar' => 'application/x-gtar',
    'h5' => 'application/x-hdf',
    'h5ad' => 'application/x-hdf'
  }.freeze

  ALLOWED_SCP_MODELS = [Study, StudyFile].freeze

  attr_accessor :client, :user_id, :file_id, :study_id, :branding_group_id

  # name of importing service (e.g. NeMO, Hca)
  def service_name
    self.class.name.split('::').last
  end

  # return hash of instance values, except for associated client
  def attributes
    instance_values.reject { |k, _| k == 'client' }
  end

  # call underlying client to load Study analog with arbitrary parameters
  def load_study(...)
    ImportService.call_api_client(client, study_method, ...)
  end

  # call underlying client to load StudyFile analog with arbitrary parameters
  def load_file(...)
    ImportService.call_api_client(client, study_file_method, ...)
  end

  # call underlying client to load BrandingGroup/Collection analog with arbitrary parameters
  def load_collection(...)
    ImportService.call_api_client(client, collection_method, ...)
  end

  def user
    User.find_by(id: user_id)
  end

  def branding_group
    BrandingGroup.find_by(id: branding_group_id)
  end

  # order of associations to walk for sourcing attributes
  # should be overwritten in included class
  def association_order
    []
  end

  # walk association_order to populate associated IDs from a starting point
  def traverse_associations!
    association_order.each do |config|
      entity_id = send(config[:id])
      entity = ImportService.call_api_client(client, config[:method], entity_id)
      associated_id = id_from(entity, config[:association])
      setter = "#{config[:assoc_id]}=" # e.g. self.study_id = 'foo'
      send(setter, associated_id)
    end
  end

  # extract an ID from an association
  def id_from(entity, ...)
    client.send(id_from_method, entity, ...)
  end

  def taxon_from(value, attribute: :common_name)
    Taxon.find_by(attribute.to_sym => value)
  end

  def taxon_names
    defined?(self.class::PREFERRED_TAXONS) ? self.class::PREFERRED_TAXONS : []
  end

  # empty hash, will be overwritten in included class
  def study_mappings
    {}
  end

  # empty hash, will be overwritten in included class
  def study_file_mappings
    {}
  end

  # empty method for getting file access info; overwrite in included class
  def file_access_info(...); end

  # create a new SCP model instance from remote data
  def to_scp_model(model, defaults, mappings, remote_data)
    raise ArgumentError, "#{model} not in #{ALLOWED_SCP_MODELS.join(', ')}" unless ALLOWED_SCP_MODELS.include?(model)

    model_attributes = defaults.dup
    mappings.each do |scp_name, config_name|
      if config_name.is_a?(Hash)
        config_name.each do |embedded_doc_attr, nested_config_name|
          model_attributes[scp_name] ||= {}
          model_attributes[scp_name][embedded_doc_attr] = remote_data[nested_config_name]
        end
      else
        model_attributes[scp_name] = remote_data[config_name]
      end
    end
    model.new(**model_attributes)
  end

  def to_study
    study_info = load_study.with_indifferent_access
    study = to_scp_model(Study, study_default_settings, study_mappings, study_info)
    study.name = sanitize_attribute(study.name)
    study.description = sanitize_attribute(study.description)
    study.external_identifier = study_id
    study
  end

  def to_study_file(study_id, taxon_common_name, taxon_attribute: :common_name, format_attribute: :file_format)
    file_info = load_file.with_indifferent_access
    study_file = to_scp_model(StudyFile, study_file_default_settings, study_file_mappings, file_info)
    # assign study, taxon, and content_type
    study_file.study_id = study_id
    study_file.taxon_id = taxon_from(taxon_common_name, attribute: taxon_attribute)&.id
    ext = file_info[format_attribute].gsub(/^\./, '') # trim leading period, if present
    study_file.upload_content_type = get_file_content_type(ext)
    study_file.external_identifier = file_id
    study_file
  end

  # get a value for library_preparation_protocol
  def find_library_prep(lib)
    sanitized_lib = lib.gsub(/(\schromium|\ssequencing)/, '')
    ExpressionFileInfo::LIBRARY_PREPARATION_VALUES.detect do |lib_prep|
      lib_prep.casecmp(sanitized_lib) == 0
    end
  end

  # empty methods to be overwritten in included classes
  # these will contain service-specific logic for sourcing data and assigning attributes to save, as well as file IO
  # this will cover cases not dealt with in default mappings and :to_study or :to_study_file
  def populate_study(...); end

  def populate_study_file(...); end

  def import_from_service(...); end

  # Main handler for saving models and pushing file to workspace bucket
  #
  # * *params*
  #   - +study+ (Study) => newly initialized Study to save
  #   - +study_file+ (StudyFile) => newly initialized StudyFile to save
  #   - +access_url+ (String) => URL to access remote file with
  #
  # * *returns*
  #   - (Array<Study, StudyFile) => newly created study & study_file to pass to ingest process
  #
  # * *raises*
  #   - (RuntimeError) => if either study or study_file fail to save correctly
  def save_models_and_push_files(study, study_file, access_url)
    log_message "Importing #{service_name} study: #{study.name} from #{study_id}"
    if study.save
      file_in_bucket = ImportService.copy_file_to_bucket(access_url, study.bucket_id, study_file.upload_file_name)
      study_file.generation = file_in_bucket.generation
      log_message "Importing #{service_name} file: #{study_file.upload_file_name} from #{file_id}"
      if study_file.save
        [study, study_file]
      else
        errors = study_file.errors.full_messages.dup
        # clean up study to allow retries with different file
        ImportService.remove_study_workspace(study)
        file_in_bucket.delete
        DeleteQueueJob.new(study).perform
        raise "could create study_file: #{errors.join('; ')}"
      end
    else
      ImportService.remove_study_workspace(study)
      errors = study.errors.full_messages.dup
      DeleteQueueJob.new(study).perform
      raise "could not create study: #{errors.join('; ')}"
    end
  end

  # remove illegal characters from an attribute value like :name or :description
  def sanitize_attribute(value)
    stripped = ActionController::Base.helpers.strip_tags(value)
    stripped.gsub(ATTRIBUTE_SANITIZER, '')
  end

  def get_file_content_type(extension)
    CONTENT_TYPES_BY_EXT[extension] || 'application/octet-stream'
  end

  # default values common to all ImportServiceConfig entities
  # can be overwritten in :study_default_settings or :study_file_default_settings
  def defaults
    {
      study: {
        public: false,
        user_id:,
        branding_group_ids: [branding_group_id]
      },
      study_file: {
        use_metadata_convention: false,
        file_type: 'AnnData',
        status: 'uploaded',
        upload_content_type: 'application/x-hdf',
        ann_data_file_info: {
          reference_file: false
        }
      }
    }
  end
end

