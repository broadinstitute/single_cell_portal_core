require 'test_helper'

module ImportServiceConfig
  class HcaTest < ActiveSupport::TestCase
    before(:all) do
      @user = FactoryBot.create(:user, test_array: @@users_to_clean)
      @branding_group = FactoryBot.create(:branding_group, user_list: [@user])
      @user_id = @user.id
      @branding_group_id = @branding_group.id
      @attributes = {
        file_id: 'b0517500-b39e-4c7a-b2f0-794ddc725433',
        study_id: '85a9263b-0887-48ed-ab1a-ddfa773727b6',
        user_id: @user.id,
        branding_group_id: @branding_group.id
      }
      @configuration = ImportServiceConfig::Hca.new(**@attributes)
      @project_name = 'Spatial and single-cell transcriptional landscape of human cerebellar development'
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
    end

    test 'should reference correct methods' do
      assert_equal :files, @configuration.study_file_method
      assert_equal :project, @configuration.study_method
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
      study = @configuration.load_study
      assert_equal @project_name, study['projectTitle']
      assert_equal 'CerebellarDevLandscape', study['projectShortname']
      assert_equal 70_000, study['estimatedCellCount']
    end

    test 'should load file analog' do
      file = @configuration.load_file
      assert_equal 'aldinger20.processed.h5ad', file['name']
      assert_equal '.h5ad', file['format']
      assert_equal 'CerebellarDevLandscape', file['projectShortname']
    end

    test 'should load taxon common names' do
      assert_equal ['Homo sapiens'], @configuration.taxon_names
    end

    test 'should find library preparation protocol' do
      assert_equal "10x 3' v3", @configuration.find_library_prep("10x chromium 3' v3 sequencing")
      assert_equal 'Drop-seq', @configuration.find_library_prep('drop-seq')
    end

    test 'should populate study and study_file' do
      scp_study = @configuration.populate_study
      assert_equal @project_name, scp_study.name
      assert_not scp_study.public
      assert_equal @user_id, scp_study.user_id
      assert_equal @branding_group_id, scp_study.branding_group_ids.first
      # populate StudyFile, using above study
      scp_study_file = @configuration.populate_study_file(scp_study.id)
      assert_not scp_study_file.use_metadata_convention
      assert_equal 'aldinger20.processed.h5ad', scp_study_file.upload_file_name
      assert_equal 'SPLiT-seq', scp_study_file.expression_file_info.library_preparation_protocol
      assert_not scp_study_file.ann_data_file_info.reference_file
    end

    # note: this is a true external integration test that creates a Terra workspace & GCP bucket
    # this is mostly to ensure that we can pull files from Azul and push them to buckets
    test 'should create study and push files to bucket' do
      attributes = @attributes.dup
      # this is a small tsv file that will copy faster
      attributes[:file_id] = 'e595263a-8f3c-452e-b00d-d87c05558102'
      config = ImportServiceConfig::Hca.new(**attributes)
      study, study_file = config.import_from_service
      assert study.persisted?
      assert study_file.persisted?
      assert study_file.uploaded?
      assert ApplicationController.firecloud_client.workspace_file_exists?(study.bucket_id, study_file.bucket_location)
      assert_equal study.external_identifier, attributes[:study_id]
      assert_equal study_file.external_identifier, attributes[:file_id]
    end
  end
end
