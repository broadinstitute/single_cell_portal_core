require 'test_helper'

module ImportServiceConfig
  class NemoTest < ActiveSupport::TestCase
    before(:all) do
      @user = FactoryBot.create(:user, test_array: @@users_to_clean)
      @branding_group = FactoryBot.create(:branding_group, user_list: [@user])
      @user_id = @user.id
      @branding_group_id = @branding_group.id
      @attributes = {
        file_id: 'nemo:der-ah1o5qb',
        project_id: 'nemo:grn-gyy3k8j',
        study_id: 'nemo:col-hwmwd2x',
        user_id: @user.id,
        branding_group_id: @branding_group.id
      }
      @configuration = ImportServiceConfig::Nemo.new(**@attributes)
    end

    after(:all) do
      StudyFile.find_by(external_identifier: @attributes[:file_id])&.destroy
      Study.find_by(external_identifier: @attributes[:study_id])&.destroy_and_remove_workspace
    end

    test 'should instantiate config' do
      config = ImportServiceConfig::Nemo.new(**@attributes)
      assert config.client.is_a?(NemoClient)
      @attributes.each do |name, value|
        assert_equal value, config.send(name)
      end
    end

    test 'should reference correct methods' do
      assert_equal :file, @configuration.study_file_method
      assert_equal :collection, @configuration.study_method
      assert_equal :extract_associated_id, @configuration.id_from_method
    end

    test 'should load associated user/collection' do
      assert_equal @user, @configuration.user
      assert_equal @branding_group, @configuration.branding_group
    end

    test 'should traverse associations to set ids' do
      config = ImportServiceConfig::Nemo.new(file_id: @attributes[:file_id])
      config.traverse_associations!
      assert_equal @attributes[:study_id], config.study_id
      assert_equal @attributes[:project_id], config.project_id
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
      study_file_mappings = @configuration.study_file_mappings
      %i[name description].each do |attribute|
        assert_equal attribute, @configuration.study_mappings[attribute]
      end
      assert_equal :file_name, study_file_mappings[:name]
      assert_equal :file_name, study_file_mappings[:upload_file_name]
      assert_equal :technique, study_file_mappings.dig(:expression_file_info, :library_preparation_protocol)
    end

    test 'should sanitize attribute values' do
      assert_equal 'filtered', @configuration.sanitize_attribute('"filtered&%$#"')
    end

    test 'should get file content type' do
      assert_equal 'application/x-hdf', @configuration.get_file_content_type('h5ad')
      assert_equal 'application/x-gtar', @configuration.get_file_content_type('tar')
      assert_equal 'application/octet-stream', @configuration.get_file_content_type('foo')
    end

    test 'should load study analog' do
      study = @configuration.load_study
      assert_equal '"Human variation study (10x), GRU"', study['name']
      assert_equal "10x chromium 3' v3 sequencing", study['technique']
      assert_equal %w[human], study['taxonomies']
    end

    test 'should load file analog' do
      file = @configuration.load_file
      assert_equal 'human_var_scVI_VLMC.h5ad.tar', file['file_name']
      assert_equal 'h5ad', file['file_format']
      assert_equal 'counts', file['data_type']
    end

    test 'should load collection analog' do
      collection = @configuration.load_collection
      assert_equal 'AIBS Internal', collection['short_name']
    end

    test 'should extract association ids' do
      file = @configuration.load_file
      study = @configuration.load_study
      assert_equal @attributes[:study_id], @configuration.id_from(file, :collections)
      assert_equal @attributes[:project_id], @configuration.id_from(study, :projects)
    end

    test 'should load taxon common names' do
      assert_equal %w[human], @configuration.taxon_common_names
    end

    test 'should populate study and study_file' do
      scp_study = @configuration.populate_study
      assert_equal 'Human variation study (10x), GRU', scp_study.name
      assert_not scp_study.public
      assert_equal @user_id, scp_study.user_id
      assert_equal @branding_group_id, scp_study.branding_group_ids.first
      # populate StudyFile, using above study
      scp_study_file = @configuration.populate_study_file(scp_study.id)
      assert scp_study_file.use_metadata_convention
      assert_equal 'human_var_scVI_VLMC.h5ad.tar', scp_study_file.upload_file_name
      assert_equal "10x 3' v3", scp_study_file.expression_file_info.library_preparation_protocol
      assert_not scp_study_file.ann_data_file_info.reference_file
    end

    # note: this is a true external integration test that creates a Terra workspace & GCP bucket
    # this is mostly to ensure that we can pull files from NeMO and push them to buckets
    test 'should create study and push files to bucket' do
      attributes = @attributes.dup
      # this is a bam.bai file that is in a public GCP bucket which allows for instant bucket->bucket copies
      attributes[:file_id] = 'nemo:alc-t6a5pxv'
      config = ImportServiceConfig::Nemo.new(**attributes)
      study, study_file = config.create_models_and_copy_files
      assert study.persisted?
      assert study_file.persisted?
      assert study_file.uploaded?
      assert ApplicationController.firecloud_client.workspace_file_exists?(study.bucket_id, study_file.bucket_location)
      assert_equal study.external_identifier, attributes[:study_id]
      assert_equal study_file.external_identifier, attributes[:file_id]
    end
  end
end
