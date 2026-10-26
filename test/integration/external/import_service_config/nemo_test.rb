require 'test_helper'
require 'detached_helper'

module ImportServiceConfig
  class NemoTest < ActiveSupport::TestCase
    before(:all) do
      @user = FactoryBot.create(:user, test_array: @@users_to_clean)
      @branding_group = FactoryBot.create(:branding_group, user_list: [@user])
      @user_id = @user.id
      @branding_group_id = @branding_group.id
      @attributes = {
        file_id: 'nemo:fil-eznvvwk',
        study_id: 'nemo:prj-2dst5ot',
        grant_id: 'nemo:prj-v7tjvn5',
        obsm_key_names: %w[X_umap],
        user_id: @user.id,
        branding_group_id: @branding_group.id
      }
      @configuration = ImportServiceConfig::Nemo.new(**@attributes)
    end

    after(:all) do
      StudyFile.find_by(external_identifier: @attributes[:file_id])&.destroy
      Study.find_by(external_identifier: @attributes[:study_id])&.destroy
    end

    test 'should instantiate config' do
      config = ImportServiceConfig::Nemo.new(**@attributes)
      assert config.client.is_a?(NemoClient)
      @attributes.each do |name, value|
        assert_equal value, config.send(name)
      end
      assert_equal @attributes[:obsm_key_names], config.obsm_keys
    end

    test 'should reference correct methods' do
      assert_equal :file, @configuration.study_file_method
      assert_equal :project, @configuration.study_method
      assert_equal :extract_associated_id, @configuration.id_from_method
    end

    test 'should return correct service name' do
      assert_equal 'NeMO', @configuration.service_name
    end

    test 'should load associated user/collection' do
      assert_equal @user, @configuration.user
      assert_equal @branding_group, @configuration.branding_group
    end

    test 'should load defaults' do
      study_defaults = {
        public: false, user_id: @user_id, branding_group_ids: [@branding_group_id]
      }.with_indifferent_access
      study_file_defaults = {
        use_metadata_convention: true,
        file_type: 'AnnData',
        status: 'uploaded',
        upload_content_type: 'application/x-hdf',
        ann_data_file_info: {
          reference_file: false
        }
      }.with_indifferent_access
      assert_equal study_defaults, @configuration.study_default_settings
      assert_equal study_file_defaults, @configuration.study_file_default_settings
    end

    test 'should load attribute mappings' do
      study_mappings = @configuration.study_mappings
      assert_equal [:title, :short_name], study_mappings[:name]
      assert_equal :description, study_mappings[:description]
      study_file_mappings = @configuration.study_file_mappings
      assert_equal :file_name, study_file_mappings[:name]
      assert_equal :file_name, study_file_mappings[:upload_file_name]
      assert_equal :techniques, study_file_mappings.dig(:expression_file_info, :library_preparation_protocol)
    end

    test 'should sanitize attribute values' do
      assert_equal 'filtered', @configuration.sanitize_attribute('"<p>filtered%$#</p>"')
    end

    test 'should get file content type' do
      assert_equal 'application/x-hdf', @configuration.get_file_content_type('h5ad')
      assert_equal 'application/x-gtar', @configuration.get_file_content_type('tar')
      assert_equal 'application/octet-stream', @configuration.get_file_content_type('csv')
    end

    test 'should load study analog' do
      study = @configuration.load_study
      assert_equal 'scorch_kenny_transcriptome', study['short_name']
      assert_includes study['techniques'], "10x chromium 3' v3 sequencing"
      assert_equal ["transcriptome"], study['modalities']
    end

    test 'should load file analog' do
      file = @configuration.load_file
      assert_equal 'ACSVABZC_POOL-16-OXY-NON-INFECTED_Batch4_IVSAOxycodoneStudy1.h5ad', file['file_name']
      assert_equal 'h5ad', file['file_format']
      assert_equal 'counts', file['data_type']
    end

    test 'should load collection analog' do
      collection = @configuration.load_collection
      assert_equal 'U01DA053629_kenny', collection.dig('grant_info', 'grant_short_name')
    end

    test 'should extract association ids' do
      file = @configuration.load_file
      expected_id = 'nemo:fil-43o57dg'
      assert_equal expected_id, @configuration.id_from(file, :parent_files, index: 0)
      config = ImportServiceConfig::Nemo.new(file_id: expected_id)
      parent_file = config.load_file
      assert_equal 'nemo:smp-f9xnr0x', config.id_from(parent_file, :sample)
    end

    test 'should load taxon common names' do
      assert_equal ["house mouse"], @configuration.taxon_names
    end

    test 'should find library preparation protocol' do
      assert_equal "10x 3' v3", @configuration.find_library_prep("10x chromium 3' v3 sequencing")
      assert_equal 'Drop-seq', @configuration.find_library_prep('drop-seq')
    end

    test 'should get sample id from file' do
      file_id = 'nemo:fil-xoawyq2'
      config = ImportServiceConfig::Nemo.new(file_id:)
      expected_sample_id = 'nemo:smp-ixjgr17'
      assert_equal expected_sample_id, config.sample_id_from_file
    end

    test 'should get remote scp ontology data' do
      efo_entries = @configuration.scp_ontology_entries('efo')
      assert efo_entries.any?
      assert_equal efo_entries["experimental factor"], "EFO_0000001"
      ncbi_taxons = @configuration.scp_ontology_entries('ncbitaxon')
      assert ncbi_taxons.any? 
      assert_equal ncbi_taxons['Homo sapiens'], 'NCBITaxon_9606'
    end

    test 'should get annotation data from file' do
      file_id = 'nemo:fil-xoawyq2'
      config = ImportServiceConfig::Nemo.new(file_id:)
      annotation_data = config.annotation_data_for_file
      expected_data = {
        biosample_id: 'Pool30_Batch3_IVSAOxycodoneStudy1',
        donor_id: 'Pool30_Batch3_IVSAOxycodoneStudy1',
        disease: 'PATO_0000461',
        disease__ontology_label: 'normal',
        library_preparation_protocol: 'EFO_0009922',
        library_preparation_protocol__ontology_label: "10x 3' v3",
        organ: 'UBERON_0001904',
        organ__ontology_label: 'habenula',
        sex: 'male',
        species: 'NCBITaxon_10090',
        species__ontology_label: 'house mouse',
      }
      expected_data.each do |key, value|
        assert_equal value, annotation_data[key]
      end
    end

    test 'should export annotation data as tsv file' do
      file_id = 'nemo:fil-xoawyq2'
      config = ImportServiceConfig::Nemo.new(file_id:)
      tsv_file = config.annotation_manifest_file
      assert File.exist?(tsv_file.path)
      contents = File.open(tsv_file.path).readlines
      headers = contents.first.split("\t").map(&:strip)
      values = contents.last.split("\t").map(&:strip)
      expected_annotations = config.annotation_data_for_file
      assert_equal expected_annotations.keys.sort, headers.sort
      assert_equal expected_annotations.values.sort, values.sort
      File.delete(tsv_file.path)
    end

    test 'should populate study and study_file' do
      scp_study = @configuration.populate_study
      project_name = 'scorch_kenny_transcriptome'
      expected_name = "#{project_name} (#{@configuration.file_id})"
      assert_equal expected_name, scp_study.name
      assert_not scp_study.public
      assert scp_study.full_description.present?
      assert_equal @user_id, scp_study.user_id
      assert_equal @branding_group_id, scp_study.branding_group_ids.first
      assert_equal @configuration.service_name, scp_study.imported_from
      # populate StudyFile, using above study
      scp_study_file = @configuration.populate_study_file(scp_study.id)
      assert scp_study_file.use_metadata_convention
      assert_equal 'ACSVABZC_POOL-16-OXY-NON-INFECTED_Batch4_IVSAOxycodoneStudy1.h5ad', scp_study_file.upload_file_name
      assert_equal "10x 3' v3", scp_study_file.expression_file_info.library_preparation_protocol
      assert_equal @configuration.service_name, scp_study_file.imported_from
      assert_not scp_study_file.ann_data_file_info.reference_file
      @configuration.obsm_keys.each do |obsm_key_name|
        assert scp_study_file.ann_data_file_info.find_fragment(data_type: :cluster, obsm_key_name:).present?
      end
      assert scp_study_file.ann_data_file_info.find_fragment(data_type: :expression).present?
    end

    test 'should import all from service' do
      access_url = 'https://data.nemoarchive.org/scorch/grant/U01DA053629_kenny/Kenny/transcriptome/nuclei/10x_v3/house_mouse/' \
                   'processed/counts/ACSVABZC_POOL-16-OXY-NON-INFECTED_Batch4_IVSAOxycodoneStudy1.h5ad'
      file_mock = ::Minitest::Mock.new
      file_mock.expect :generation, '123456789'
      # for study to save, we need to mock all Terra orchestration API calls for creating workspace & setting acls
      fc_client_mock = ::Minitest::Mock.new
      owner_group = { groupEmail: 'sa-owner-group@firecloud.org' }.with_indifferent_access
      assign_workspace_mock!(fc_client_mock, owner_group, 'scorch-kenny-transcriptome-nemo-fil-eznvvwk')
      AdminConfiguration.stub :find_or_create_ws_user_group!, owner_group do
        ImportService.stub :copy_file_to_bucket, file_mock do
          ApplicationController.stub :firecloud_client, fc_client_mock do
            @configuration.stub :taxon_from, Taxon.new(common_name: 'human') do
              study, study_file = @configuration.import_from_service
              file_mock.verify
              fc_client_mock.verify
              assert study.persisted?
              assert study_file.persisted?
              assert_equal study.external_identifier, @attributes[:study_id]
              assert_equal study_file.external_identifier, @attributes[:file_id]
              assert_equal study_file.external_link_url, access_url
            end
          end
        end
      end
    end
  end
end
