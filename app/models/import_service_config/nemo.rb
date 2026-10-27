module ImportServiceConfig
  # methods/configurations for importing data from NeMO Identifiers API
  class Nemo
    include ImportServiceConfig

    attr_accessor :grant_id

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
      :project
    end

    def load_study
      super(study_id)
    end

    # name of entity/method to call for loading analog of a BrandingGroup/Collection
    def collection_method
      :grant
    end

    def load_collection
      super(grant_id)
    end

    def id_from_method
      :extract_associated_id
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
      load_study&.[]('taxa')&.map { |t| t['name']}.presence || load_collection&.[]('taxa')&.map { |t| t['name']}.presence || []
    end

    # map attribute names SCP Study attributes onto NeMO attribute names
    def study_mappings
      {
        name: [:title, :short_name], # fallback in case of empty title
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
      scp_study = to_study
      current_name = scp_study.name
      grant = load_collection
      grant_name = grant.dig('grant_info', 'grant_title')
      filename = load_file&.[]('file_name')
      scp_study.name = "#{current_name} (#{file_id})"
      scp_study.description += " from #{filename} in '#{grant_name}'"
      scp_study.study_detail.full_description = sanitize_attribute(scp_study.description)
      scp_study
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

    # use the API to find an associated sample ID for a given file, either directly or via parent files
    # 
    # * *returns*
    #   - (String) => sample ID in nemo:smp-[a-z0-9]{7}$ form, or nil if no sample association is found
    def sample_id_from_file
      file = load_file
      if file['sample'].present?
        client.extract_associated_id(file, :sample)
      elsif file['parent_files'].present?
        ids = client.extract_associated_ids(file, :parent_files)
        samples = ids.map do |parent_file_id|
          parent_file = client.file(parent_file_id)
          client.extract_associated_id(parent_file, :sample)
        end
        samples.uniq.first # there should only ever be one sample for an analysis h5ad file
      else
        nil
      end
    end

    # traverse associations in API to retrive sample- and subject-level data to export as annotation data
    #
    # * *returns*
    #   - (Hash) => annotation data for study_file, or nil if no associated sample is found
    def annotation_data_for_file
      sample_id = sample_id_from_file
      return nil unless sample_id

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
      lib_name = find_library_prep(library_name)
      library_preparation_protocol = scp_ontology_entries('efo')[lib_name]
      # all NeMO entires carry no disease annotation, so every sample is treated
      # as unaffected/normal per the PATO convention for a missing disease state.
      disease_label = 'normal'
      disease = scp_ontology_entries('pato')[disease_label]
      { 
        biosample_id: sample['sample_name'], donor_id: sample['sample_name'],
        disease:, disease__ontology_label: disease_label,
        library_preparation_protocol:, library_preparation_protocol__ontology_label: lib_name,
        organ: organ.gsub(/\:/, '_'), organ__ontology_label: organ_label, sample_id:, sex:, 
        species: "NCBITaxon_#{taxon_id}", species__ontology_label: species_name
      }.reject { |_, v| v.blank? }.with_indifferent_access
    end

    # transform annotation data into a tsv manifest to project onto an AnnData file for ingest
    #
    # * *returns*
    #   - (File) => annotation data in tsv file format
    def annotation_manifest_file
      return nil unless file_id

      filename = file_id.split(':').last
      FileUtils.mkdir_p('tmp/uploads/nemo_manifests')
      outfile = File.open(Rails.root.join('tmp', "uploads", "nemo_manifests", "#{filename}.scp.tsv"), 'w+')
      annotations = annotation_data_for_file
      headers = annotations.keys
      values = annotations.values
      outfile.write(headers.join("\t") + "\n")
      outfile.write(values.join("\t") + "\n")
      outfile.close
      outfile
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

      study = populate_study
      study_file = populate_study_file(study.id)
      nemo_gs_url = file_access_info(protocol: :gs)&.[]('url')
      # gotcha for some GS urls having an incorrect root folder, this likely is something that will be fixed with
      # the public release but for now leaving this hack in place
      nemo_gs_url&.gsub!(/biccn_unbundled/, 'biccn-unbundled')
      nemo_http_url = file_access_info(protocol: :http)&.[]('url')
      access_url = nemo_http_url || nemo_gs_url
      raise "could not obtain file access info for #{file_id}" if access_url.blank?

      download_url = nemo_http_url || nemo_gs_url
      study_file.external_link_url = download_url
      study_file.external_link_title = 'NeMO Download'
      scp_study, scp_study_file = save_models_and_push_files(study, study_file, access_url)
      file_manifest = annotation_manifest_file
      ApplicationController.firecloud_client.create_workspace_file(scp_study.bucket_id, file_manifest.path)
      FileParseService.run_parse_job(scp_study_file, scp_study, study.user)
    end
  end
end
