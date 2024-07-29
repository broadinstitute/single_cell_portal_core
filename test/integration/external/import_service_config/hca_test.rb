require 'test_helper'
require 'detached_helper'

module ImportServiceConfig
  class HcaTest < ActiveSupport::TestCase
    before(:all) do
      @user = FactoryBot.create(:user, test_array: @@users_to_clean)
      @branding_group = FactoryBot.create(:branding_group, user_list: [@user])
      @user_id = @user.id
      @branding_group_id = @branding_group.id
      @attributes = {
        file_id: '6e63e10e-7a5f-52b8-9242-df9d169b802a',
        study_id: '74b6d569-3b11-42ef-b6b1-a0454522b4a0',
        obsm_key_names: %w[X_tsne X_umap],
        user_id: @user.id,
        branding_group_id: @branding_group.id
      }
      @configuration = ImportServiceConfig::Hca.new(**@attributes)
      @project_name = '1.3 Million Brain Cells from E18 Mice'

      @azul_is_ok = false
      begin
        project = @configuration.load_study
        file = @configuration.load_file
        if project && file
          @azul_is_ok = true
        end
      rescue RestClient::Exception => e
        puts "Error in determining if Azul is healthy: #{e.message}"
      end
      @skip_message = '-- skipping due to Azul API being unavailable or inconsistent --'
    end

    # skip a test if Azul is not up ; prevents unnecessary build failures due to releases/maintenance
    def skip_if_api_down
      unless @azul_is_ok
        puts @skip_message; skip
      end
    end

    after(:all) do
      StudyFile.find_by(external_identifier: @attributes[:file_id])&.destroy
      Study.find_by(external_identifier: @attributes[:study_id])&.destroy_and_remove_workspace
    end

    test 'should instantiate config' do
      config = ImportServiceConfig::Hca.new(**@attributes)
      assert config.client.is_a?(HcaAzulClient)
      @attributes.each do |name, value|
        assert_equal value, config.send(name)
      end
      assert_equal @attributes[:obsm_key_names], config.obsm_keys
    end

    test 'should reference correct methods' do
      assert_equal :files, @configuration.study_file_method
      assert_equal :project, @configuration.study_method
    end

    test 'should return correct service name' do
      assert_equal 'HCA', @configuration.service_name
    end

    test 'should load defaults' do
      study_defaults = {
        public: false, user_id: @user_id, branding_group_ids: [@branding_group_id]
      }.with_indifferent_access
      study_file_defaults = {
        use_metadata_convention: false,
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
      study_file_mappings = @configuration.study_file_mappings
      assert_equal :projectTitle, study_mappings[:name]
      assert_equal :projectDescription, study_mappings[:description]
      assert_equal :name, study_file_mappings[:name]
      assert_equal :name, study_file_mappings[:upload_file_name]
      assert_equal :contentDescription, study_file_mappings[:description]
      assert_equal :libraryConstructionApproach,
                   study_file_mappings.dig(:expression_file_info, :library_preparation_protocol)
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
      skip_if_api_down
      study = @configuration.load_study
      assert_equal @project_name, study['projectTitle']
      assert_equal '1M Neurons', study['projectShortname']
      assert_equal 1_330_000, study['estimatedCellCount']
    end

    test 'should load file analog' do
      skip_if_api_down
      file = @configuration.load_file
      assert_equal '1M_neurons_filtered_gene_bc_matrices_h5.h5', file['name']
      assert_equal 'h5', file['format']
      assert_equal '1M Neurons', file['projectShortname']
    end

    test 'should load taxon common names' do
      skip_if_api_down
      assert_equal ["Mus musculus"], @configuration.taxon_names
    end

    test 'should find library preparation protocol' do
      skip_if_api_down
      assert_equal "10x 3' v3", @configuration.find_library_prep("10x chromium 3' v3 sequencing")
      assert_equal 'Drop-seq', @configuration.find_library_prep('drop-seq')
    end

    test 'should populate study and study_file' do
      skip_if_api_down
      scp_study = @configuration.populate_study
      assert_equal @project_name, scp_study.name
      assert_not scp_study.public
      assert scp_study.full_description.present?
      assert_equal @user_id, scp_study.user_id
      assert_equal @branding_group_id, scp_study.branding_group_ids.first
      assert_equal @configuration.service_name, scp_study.imported_from
      # populate StudyFile, using above study
      scp_study_file = @configuration.populate_study_file(scp_study.id)
      assert_not scp_study_file.use_metadata_convention
      assert_equal '1M_neurons_filtered_gene_bc_matrices_h5.h5', scp_study_file.upload_file_name
      assert_equal "10x 3' v2", scp_study_file.expression_file_info.library_preparation_protocol
      assert_equal @configuration.service_name, scp_study_file.imported_from
      assert_not scp_study_file.ann_data_file_info.reference_file
      @configuration.obsm_keys.each do |obsm_key_name|
        assert scp_study_file.ann_data_file_info.find_fragment(data_type: :cluster, obsm_key_name:).present?
      end
      assert scp_study_file.ann_data_file_info.find_fragment(data_type: :expression).present?
    end

    test 'should import from service' do
      skip_if_api_down
      study_name = '1-3-million-brain-cells-from-e18-mice'
      access_url = @configuration.file_access_info
      file_mock = MiniTest::Mock.new
      file_mock.expect :generation, '123456789'
      # for study to save, we need to mock all Terra orchestration API calls for creating workspace & setting acls
      fc_client_mock = Minitest::Mock.new
      owner_group = { groupEmail: 'sa-owner-group@firecloud.org' }.with_indifferent_access
      admin_group = { groupEmail: "#{FireCloudClient::ADMIN_INTERNAL_GROUP_NAME}@firecloud.org" }.with_indifferent_access
      assign_workspace_mock!(fc_client_mock, owner_group, study_name)
      AdminConfiguration.stub :find_or_create_ws_user_group!, owner_group do
        AdminConfiguration.stub :find_or_create_admin_internal_group!, admin_group do
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
                # trim off query params to prevent test failures when catalog/version updates
                trimmed_access_url = access_url.split('?').first
                trimmed_external_url = study_file.external_link_url.split('?').first
                assert_equal trimmed_external_url, trimmed_access_url
              end
            end
          end
        end
      end
    end
  end
end
