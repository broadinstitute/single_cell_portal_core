require 'test_helper'
require 'api_test_helper'
require 'includes_helper'

class ExpressionControllerTest < ActionDispatch::IntegrationTest

  before(:all) do
    @user = FactoryBot.create(:api_user, test_array: @@users_to_clean)
    @basic_study = FactoryBot.create(:detached_study,
                                     name_prefix: 'Basic Expression Study',
                                     public: false,
                                     user: @user,
                                     test_array: @@studies_to_clean)

    @basic_study_cluster_file = FactoryBot.create(:cluster_file,
                                                  name: 'clusterA.txt',
                                                  study: @basic_study,
                                                  cell_input: {
                                                     x: [1, 4 ,6],
                                                     y: [7, 5, 3],
                                                     cells: ['A', 'B', 'C']
                                                  },
                                                  annotation_input: [{name: 'foo', type: 'group', values: ['bar', 'bar', 'baz']}])

    @basic_study_metadata_file = FactoryBot.create(:metadata_file,
                                                   name: 'metadata.txt',
                                                   study: @basic_study,
                                                   cell_input: ['A', 'B', 'C'],
                                                   annotation_input: [
                                                     {name: 'species', type: 'group', values: ['dog', 'cat', 'dog']},
                                                     {name: 'disease', type: 'group', values: ['none', 'none', 'measles']}
                                                   ])
    @basic_study_exp_file = FactoryBot.create(:study_file,
                                              name: 'dense.txt',
                                              file_type: 'Expression Matrix',
                                              taxon: Taxon.first,
                                              study: @basic_study)
    @pten_gene = FactoryBot.create(:gene_with_expression,
                                   name: 'PTEN',
                                   gene_id: 'ENSG00000171862',
                                   study_file: @basic_study_exp_file,
                                   expression_input: [['A', 0],['B', 3],['C', 1.5]])

    @empty_study = FactoryBot.create(:detached_study,
                                     name_prefix: 'Empty Expression Study',
                                     public: false,
                                     user: @user,
                                     test_array: @@studies_to_clean)
  end

  teardown do
    OmniAuth.config.mock_auth[:google_oauth2] = nil
  end

  test 'methods should check view permissions' do
    sign_in_and_update @user
    execute_http_request(:get, api_v1_study_expression_path(@basic_study, 'heatmap', {
      cluster: 'clusterA.txt',
      genes: 'PTEN'
    }), user: @user)
    assert_equal 200, response.status

    user2 = FactoryBot.create(:api_user, test_array: @@users_to_clean)
    sign_in_and_update user2

    execute_http_request(:get, api_v1_study_expression_path(@basic_study, 'heatmap'), user: user2)
    assert_equal 403, response.status
  end

  test 'methods should return expected values' do
    sign_in_and_update @user
    execute_http_request(:get, api_v1_study_expression_path(@basic_study, 'heatmap', {
      cluster: 'clusterA.txt',
      genes: 'PTEN'
    }), user: @user)
    assert_equal 200, response.status
    assert_equal "#1.2\n1\t3\nName\tDescription\tA\tB\tC\nPTEN\t\t0.0\t3.0\t1.5", response.body

    execute_http_request(:get, api_v1_study_expression_path(@empty_study, 'heatmap', {
      cluster: 'clusterA.txt',
      genes: 'PTEN'
    }), user: @user)
    assert_equal 400, response.status # 400 since study is not visualizable

    execute_http_request(:get, api_v1_study_expression_path(@basic_study, 'violin', {
      cluster: 'clusterA.txt',
      genes: 'PTEN'
    }), user: @user)
    assert_equal 200, response.status
    expected = { y: [0.0, 3.0], cells: %w(A B), annotations: [], name: 'bar', color: '#e41a1c' }.with_indifferent_access
    assert_equal expected, json['values']['bar']

    execute_http_request(:get, api_v1_study_expression_path(@empty_study, 'violin', {
      cluster: 'clusterA.txt',
      genes: 'PTEN'
    }), user: @user)
    assert_equal 400, response.status # 400 since study is not visualizable
  end

  test 'should render precomputed dotplot data' do
    cluster = @basic_study.cluster_groups.first
    exp_scores = @basic_study.cell_metadata.map do |metadata|
      {
        metadata.annotation_select_value => metadata.values.map do |value|
          { value => [rand.round(3), rand.round(3)] }
        end.reduce({}, :merge)
      }
    end.reduce({}, :merge)
    genes = %w[PTEN AGPAT2 PHEX FARSA GAD1 EGFR CLDN4]
    genes.each do |gene_symbol|
      DotPlotGene.create(
        study: @basic_study,
        study_file: @basic_study_exp_file,
        cluster_group: cluster,
        gene_symbol:,
        exp_scores:
      )
    end
    sign_in_and_update @user
    annotation = @basic_study.cell_metadata.where(annotation_type: 'group').sample
    execute_http_request(:get, api_v1_study_expression_path(@basic_study, 'dotplot', {
      cluster: cluster.name,
      annotation_name: annotation.name,
      annotation_type: 'group',
      annotation_scope: 'study',
      genes: genes.join(',')
    }), user: @user)
    assert_equal 200, response.status
    gene_entry = json.dig('genes', genes.sample)
    assert_equal exp_scores[annotation.annotation_select_value].values, gene_entry
  end

  test 'should query by gene ID' do
    gene_id = @basic_study.genes.first.gene_id
    sign_in_and_update @user
    execute_http_request(:get, api_v1_study_expression_path(@basic_study, 'heatmap', {
      cluster: 'clusterA.txt',
      genes: gene_id
    }), user: @user)
    assert_equal 200, response.status
    # will still use gene symbol in response body
    assert_equal "#1.2\n1\t3\nName\tDescription\tA\tB\tC\nPTEN\t\t0.0\t3.0\t1.5", response.body
  end

  test "should prevent searches over #{StudySearchService::MAX_GENE_SEARCH} genes" do
    genes = 1.upto(100).map { |i| "Gene_#{i}" }.join(',')
    sign_in_and_update @user
    execute_http_request(:get, api_v1_study_expression_path(
      @basic_study, 'heatmap', { cluster: 'clusterA.txt', genes: genes }
    ), user: @user)
    assert_response :unprocessable_entity
  end

  test 'should reject bogus requests' do
    sign_in_and_update @user
    %w[xssdetected UPDATEXML CODE_POINTS_TO_STRING .git].each do |bogus|
      execute_http_request(:get, api_v1_study_expression_path(@basic_study, 'violin', {
        cluster: bogus,
        genes: 'PTEN'
      }), user: @user)
      assert_response :bad_request
      execute_http_request(:get, api_v1_study_expression_path(@basic_study, 'violin', {
        cluster: 'clusterA.txt',
        genes: bogus
      }), user: @user)
      assert_response :bad_request
    end
  end
end
