require 'test_helper'

class ParseUtilsTest < ActiveSupport::TestCase

  before(:all) do
    @user = FactoryBot.create(:api_user, test_array: @@users_to_clean)
    @basic_study = FactoryBot.create(:detached_study,
                                     name_prefix: 'Parse Utils Test',
                                     user: @user,
                                     test_array: @@studies_to_clean)
  end


  test 'should parse gene list file' do
    gene_list_name = 'Test Gene List'
    File.open(Rails.root.join('test', 'test_data', 'marker_1_gene_list.txt')) do |gene_list_file|
      StudyFile.create(study_id: @basic_study.id, upload: gene_list_file, file_type: 'Gene List',
                       name: gene_list_name)
      gene_list_file.close
    end

    gene_list = @basic_study.study_files.by_type('Gene List').first
    # add mocks to skip pushing file to bucket
    file_mock = Minitest::Mock.new
    file_mock.expect :nil?, true
    2.times { file_mock.expect :generation, '1234567890' }
    mock = Minitest::Mock.new
    mock.expect :get_study_bucket_file, file_mock, [@basic_study.bucket_id, gene_list.bucket_location]
    mock.expect :create_study_bucket_file, file_mock,
                [@basic_study.bucket_id, String, String], **{ content_encoding: 'gzip' }
    StorageService.stub :load_client, mock do
      ParseUtils.initialize_precomputed_scores(@basic_study, gene_list, @user)
      precomputed_score = @basic_study.precomputed_scores.find_by(name: gene_list_name)
      assert precomputed_score.present?
      mock.verify
      expected_clusters = %w(CLST_A CLST_B CLST_C)
      assert_equal expected_clusters, precomputed_score.clusters
      assert_equal 5, precomputed_score.gene_scores.size
    end
  end
end
