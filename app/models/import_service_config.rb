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

  # return hash of instance values, except for associated client
  def attributes
    instance_values.reject { |k, _| k == 'client' }
  end

  def load_study
    ImportService.call_api_client(client, study_method, study_id)
  end

  def load_file
    ImportService.call_api_client(client, study_file_method, file_id)
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

  def taxon_from(common_name)
    Taxon.find_by(common_name:)
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

  def to_study_file(study_id, taxon_common_name)
    file_info = load_file.with_indifferent_access
    study_file = to_scp_model(StudyFile, study_file_default_settings, study_file_mappings, file_info)
    # assign study, taxon, and content_type
    study_file.study_id = study_id
    study_file.taxon_id = taxon_from(taxon_common_name)&.id
    ext = file_info['file_format']
    study_file.upload_content_type = get_file_content_type(ext)
    study_file.external_identifier = file_id
    study_file
  end

  # empty methods to be overwritten in included classes
  # these will contain service-specific logic for sourcing data and assigning attributes to save, as well as file IO
  # this will cover cases not dealt with in default mappings and :to_study or :to_study_file
  def populate_study(...); end

  def populate_study_file(...); end

  def create_models_and_copy_files(...); end

  # remove illegal characters from an attribute value like :name or :description
  def sanitize_attribute(value)
    value.gsub(ATTRIBUTE_SANITIZER, '')
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

