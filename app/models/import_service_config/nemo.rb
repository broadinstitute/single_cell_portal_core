module ImportServiceConfig
  # methods/configurations for importing data from NeMO Identifiers API
  class Nemo
    include ImportServiceConfig

    attr_accessor :project_id

    validates :file_id, :user_id, :branding_group_id, presence: true

    PREFERRED_TAXONS = %w[human mouse].freeze

    # name for logging when calling ImportService.import_from
    SERVICE_NAME = 'NeMO'.freeze

    def initialize(attributes = {})
      super
      @client ||= ::NemoClient.new
    end

    # name of entity/method to call for loading analog of StudyFile
    def study_file_method
      :file
    end

    def load_file
      super(file_id)
    end

    # name of entity/method to call for loading analog of Study
    def study_method
      :collection
    end

    def load_study
      super(study_id)
    end

    # name of entity/method to call for loading analog of a BrandingGroup/Collection
    def collection_method
      :project
    end

    def load_collection
      super(project_id)
    end

    def id_from_method
      :extract_associated_id
    end

    # recursively fetch associations to get other identifiers
    def association_order
      [
        { method: study_file_method, association: :collections, id: :file_id, assoc_id: :study_id },
        { method: study_method, association: :projects, id: :study_id, assoc_id: :project_id }
      ]
    end

    # return hash of file access info, like url, sizes, etc
    def file_access_info(protocol: nil)
      urls = load_file&.[]('manifest_file_urls')
      protocol ? urls.detect { |url| url.with_indifferent_access[:protocol] == protocol.to_s } : urls
    end

    def study_default_settings
      defaults[:study].with_indifferent_access
    end

    def study_file_default_settings
      defaults[:study_file].merge(use_metadata_convention: true).with_indifferent_access
    end

    # retrieve common species names from associated collection
    def taxon_names
      load_study&.[]('taxa')&.map { |t| t['name']} || []
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
          library_preparation_protocol: :techniques
        }
      }.with_indifferent_access
    end

    # service-specific logic for assigning attributes
    # each config should implement these methods to deal with corner cases in assigning attributes
    # if there are no validation issues, these can simple call the :to_{model} methods as a passthru
    def populate_study
      to_study
    end

    def populate_study_file(scp_study_id)
      taxons = taxon_names
      preferred_name = taxons.detect { |name| PREFERRED_TAXONS.include?(name) } || taxons.first
      study_file = to_study_file(scp_study_id, preferred_name)
      library = study_file.expression_file_info.library_preparation_protocol
      if library.blank?
        libs = load_study&.[]('techniques')
        libraries = libs.map { |lib| find_library_prep(lib) }.compact
        study_file.expression_file_info.library_preparation_protocol = libraries.first
      end
      exp_fragment = expression_data_fragment(study_file)
      study_file.ann_data_file_info.data_fragments << exp_fragment
      http_url = file_access_info(protocol: :http)&.[]('url')
      study_file.external_link_url = http_url if http_url
      study_file
    end

    # traverse associations in API to retrive sample- and subject-level data to export as annotation data
    #
    # * *returns*
    #  - (Array<Hash>) => array of hashes with annotation data for study_file
    def annotation_data_for_file
      file = load_file
      if file['sample'].blank?
        ids = client.extract_associated_ids(file, :parent_files)
        samples = []
        ids.each do |parent_file_id|
          parent_file = client.file(parent_file_id)
          samples << client.extract_associated_id(parent_file, :sample)
        end
        samples.uniq!
        sample_id = samples.first
      else
        sample_id = client.extract_associated_id(file, :sample)
      end
      sample = client.sample(sample_id)
      library_name = client.extract_associated_id(sample, :libraries, attribute: :technique)
      subject_id = client.extract_associated_id(sample, :subjects)
      subject = client.subject(subject_id)
      species_name = client.extract_associated_id(subject, :taxa, attribute: :name)
      sex_idx = subject['subject_attributes'].index {|attr| attr['name'] == 'sex'}
      sex = client.extract_associated_id(subject, :subject_attributes, index: sex_idx, attribute: :value) if sex_idx
      taxon_id = client.extract_associated_id(subject, :taxa, attribute: :cv_term_id).split('NCBI:txid')&.last
      organ_label = client.extract_associated_id(sample, :anatomical_regions, attribute: :region_name)
      organ = client.extract_associated_id(sample, :anatomical_regions, attribute: :cv_term_id)
      { 
        library_preparation_protocol: find_library_prep(library_name),
        species__ontology_label: species_name, sex:, species: "NCBITaxon_#{taxon_id}",
        organ__ontology_label: organ_label, organ: organ.gsub(/\:/, '_')
      }.reject { |_, v| v.blank? }.with_indifferent_access
    end

    # main business logic of populating SCP models for NeMO data
    #
    # * *returns*
    #   - (Array<Study, StudyFile) => newly created study & study_file
    #
    # * *raises*
    #   - (RuntimeError) => if either study or study_file fail to save correctly
    #   - (ArgumentError) => if no file_id is provided
    def import_from_service
      raise configuration.errors.full_messages.join(', ') unless valid?

      traverse_associations! unless study_id
      study = populate_study
      study_file = populate_study_file(study.id)
      nemo_gs_url = file_access_info(protocol: :gs)&.[]('url')
      # gotcha for some GS urls having an incorrect root folder, this likely is something that will be fixed with
      # the public release but for now leaving this hack in place
      nemo_gs_url&.gsub!(/biccn_unbundled/, 'biccn-unbundled')
      nemo_http_url = file_access_info(protocol: :http)&.[]('url')
      access_url = nemo_gs_url || nemo_http_url
      raise "could not obtain file access info for #{file_id}" if access_url.blank?

      download_url = nemo_http_url || nemo_gs_url
      study_file.external_link_url = download_url
      study_file.external_link_title = 'NeMO Download'
      save_models_and_push_files(study, study_file, access_url)
    end
  end
end
