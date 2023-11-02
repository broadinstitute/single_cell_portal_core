module ImportServiceConfig
  # methods/configurations for importing data from NeMO Identifiers API
  class Nemo
    include ImportServiceConfig::Base

    attr_accessor :project_id

    def initialize(attributes = {})
      super
      @client ||= ::NemoClient.new
    end

    # name of entity/method to call for loading analog of StudyFile
    def study_file_method
      :file
    end

    # name of entity/method to call for loading analog of Study
    def study_method
      :collection
    end

    # load a NeMO project, which is an analog for BrandingGroups/Collections
    def load_project
      ImportService.call_api_client(client, :project, project_id)
    end

    def id_from_method
      :extract_associated_id
    end

    # return hash of file access info, like url, sizes, etc
    def file_access_info(protocol: :gs)
      urls = load_file&.[]('urls')
      urls.detect { |url| url.with_indifferent_access[:protocol] == protocol.to_s }
    end

    def study_default_settings
      defaults[:study].with_indifferent_access
    end

    def study_file_default_settings
      defaults[:study_file].merge(use_metadata_convention: true).with_indifferent_access
    end

    # map attribute names SCP Study attributes onto NeMO attribute names
    def study_mappings
      {
        name: :name,
        description: :description
      }.with_indifferent_access
    end

    # map attribute names from SCP StudyFile attributes onto NeMO attribute names
    def study_file_mappings
      {
        upload_file_name: :file_name,
        upload_file_size: :size,
        name: :file_name,
        expression_file_info_attributes: {
          library_preparation_protocol: :technique
        }
      }.with_indifferent_access
    end
  end
end
