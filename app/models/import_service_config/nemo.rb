module ImportServiceConfig
  # methods/configurations for importing data from NeMO Identifiers API
  class Nemo
    include ImportServiceConfig::Base

    attr_accessor :project_id

    PREFERRED_TAXONS = %w[human mouse]

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
    def file_access_info(protocol: nil)
      urls = load_file&.[]('urls')
      protocol ? urls.detect { |url| url.with_indifferent_access[:protocol] == protocol.to_s } : urls
    end

    def study_default_settings
      defaults[:study].with_indifferent_access
    end

    def study_file_default_settings
      defaults[:study_file].merge(use_metadata_convention: true).with_indifferent_access
    end

    # retrieve common species names from associated collection
    def taxon_common_names
      load_study&.[]('taxonomies') || []
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
        expression_file_info: {
          library_preparation_protocol: :technique
        }
      }.with_indifferent_access
    end

    # service-specific logic for assigning attributes
    # each config should implement these methods to deal with corner cases in assigning attributes
    # if there are no validation issues, these can simple call the :to_{model} methods as a passthru
    def populate_study
      to_study
    end

    def populate_study_file(study_id)
      taxon_names = taxon_common_names
      preferred_name = taxon_names.detect { |name| PREFERRED_TAXONS.include?(name) } || taxon_names.first
      study_file = to_study_file(study_id, preferred_name)
      if study_file.expression_file_info.library_preparation_protocol.blank?
        raw_library_prep = load_study&.[]('technique')
        library_prep = raw_library_prep.gsub(/(\schromium|\ssequencing)/, '')
        study_file.expression_file_info.library_preparation_protocol = library_prep
      end
      study_file
    end

    # main business logic of creating SCP models, saving to database and moving file to workspace bucket for ingest
    # will also set external_link_url such that file can be downloaded directly from NeMO
    #
    # * *returns*
    #   - (Array<Study, StudyFile) => newly created study & study_file to pass to ingest process
    #
    # * *raises*
    #   - (RuntimeError) => if either study or study_file fail to save correctly
    def create_models_and_copy_files
      study = populate_study
      if study.save
        study_file = populate_study_file(study.id)
        nemo_gs_url = file_access_info(protocol: :gs)&.[]('url')
        nemo_http_url = file_access_info(protocol: :http)&.[]('url')
        access_url = nemo_gs_url || nemo_http_url
        raise "could not obtain file access info for #{file_id}" if access_url.blank?

        download_url = nemo_http_url || nemo_gs_url
        study_file.external_link_url = download_url
        study_file.external_link_title = 'NeMO Download'
        file_in_bucket = ImportService.copy_file_to_bucket(access_url, study.bucket_id)
        study_file.generation = file_in_bucket.generation
        if study_file.save
          [study, study_file]
        else
          errors = study_file.errors.full_messages.dup
          # clean up study to allow retries with different file
          ApplicationController.firecloud_client.delete_workspace(study.firecloud_project, study.firecloud_workspace)
          file_in_bucket.delete
          DeleteQueueJob.new(study).perform
          DeleteQueueJob.new(study_file).perform
          raise "could create study_file: #{errors.join('; ')}"
        end
      else
        errors = study.errors.full_messages.dup
        DeleteQueueJob.new(study).perform
        raise "could not create study: #{errors.join('; ')}"
      end
    end
  end
end
