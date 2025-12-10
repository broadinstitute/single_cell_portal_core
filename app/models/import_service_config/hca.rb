module ImportServiceConfig
  # stub configurations for importing atlas datasets from HCA Azul service
  class Hca
    include ImportServiceConfig

    PREFERRED_TAXONS = ['Homo sapiens', 'Mus musculus'].freeze

    validates :file_id, :study_id, :user_id, :branding_group_id, presence: true

    # name for logging when calling ImportService.import_from
    SERVICE_NAME = 'HCA'.freeze

    def initialize(attributes = {})
      super
      @client ||= ::HcaAzulClient.new
    end

    # name of entity/method to call for loading analog of StudyFile
    def study_file_method
      :files
    end

    def load_file
      query = { 'projectId' => { 'is' => [study_id] }, 'fileId' => { 'is' => [file_id] } }
      super(query:)&.first
    end

    # name of entity/method to call for loading analog of Study
    def study_method
      :project
    end

    # special method to get outer information for HCA projects
    # this is due to JSON structure returned where key information is outside :projects array
    def raw_study
      ImportService.call_api_client(client, study_method, study_id)
    end

    def load_study
      super(study_id)&.[]('projects')&.first
    end

    # overwriting methods as they have no analog in Azul
    def collection_method; end
    def load_collection; end
    def id_from_method; end
    def id_from; end

    def file_access_info
      load_file&.[]('azul_url')
    end

    def study_default_settings
      defaults[:study].with_indifferent_access
    end

    def study_file_default_settings
      defaults[:study_file].with_indifferent_access
    end

    def taxon_names
      raw_study['donorOrganisms'].map { |organism| organism['genusSpecies'] }.flatten
    end

    def study_mappings
      {
        name: :projectTitle,
        description: :projectDescription
      }
    end

    def study_file_mappings
      {
        name: :name,
        description: :contentDescription,
        upload_file_name: :name,
        upload_file_size: :size,
        expression_file_info: {
          library_preparation_protocol: :libraryConstructionApproach
        }
      }
    end

    def populate_study
      to_study
    end

    def populate_study_file(scp_study_id)
      taxons = taxon_names
      preferred_name = taxons.detect { |name| PREFERRED_TAXONS.include?(name) } || taxons.first
      study_file = to_study_file(
        scp_study_id, preferred_name, taxon_attribute: :scientific_name, format_attribute: :format
      )
      if study_file.expression_file_info.library_preparation_protocol.blank?
        libraries = raw_study&.[]('protocols')&.map { |p| p['libraryConstructionApproach'] }&.flatten&.compact || []
        found_libs = libraries.map { |lib| find_library_prep(lib) }.compact
        study_file.expression_file_info.library_preparation_protocol = found_libs.first
      end
      exp_fragment = expression_data_fragment(study_file)
      study_file.ann_data_file_info.data_fragments << exp_fragment
      study_file
    end

    # main business logic of populating SCP models for HCA Azul projects
    #
    # * *returns*
    #   - (Array<Study, StudyFile) => newly created study & study_file
    #
    # * *raises*
    #   - (RuntimeError) => if either study or study_file fail to save correctly
    #   - (ArgumentError) => if no file_id & study_id are not provided
    def import_from_service
      raise configuration.errors.full_messages.join(', ') unless valid?

      study = populate_study
      study_file = populate_study_file(study.id)
      access_url = file_access_info
      study_file.external_link_url = access_url
      study_file.external_link_title = 'HCA Download'
      save_models_and_push_files(study, study_file, access_url)
    end
  end
end
