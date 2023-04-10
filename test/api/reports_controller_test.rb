require 'api_test_helper'
require 'test_helper'
require 'includes_helper'

class ReportsControllerTest < ActionDispatch::IntegrationTest

  before(:all) do
    @user = FactoryBot.create(:api_user, test_array: @@users_to_clean)
    @admin_user = FactoryBot.create(:admin_user, admin: true, test_array: @@users_to_clean)
    @study = FactoryBot.create(:detached_study,
                               name_prefix: 'ReportsController Study',
                               public: true,
                               user: @user,
                               test_array: @@studies_to_clean)

    FactoryBot.create(:cluster_file,
                      name: 'clusterA.txt',
                      study: @study,
                      cell_input: {
                        x: [1, 4, 6],
                        y: [7, 5, 3],
                        cells: %w[A B C D]
                      },
                      annotation_input: [{ name: 'foo', type: 'group', values: %w[bar bar baz baz] }])

    FactoryBot.create(:metadata_file,
                      name: 'metadata.txt',
                      study: @study,
                      cell_input: %w[A B C D],
                      annotation_input: [
                        { name: 'species', type: 'group', values: %w[dog cat dog cat] },
                        { name: 'disease', type: 'group', values: %w[none none measles measles] }
                      ])
    matrix = FactoryBot.create(:study_file,
                      name: 'dense.txt',
                      file_type: 'Expression Matrix',
                      study: @study)
    DifferentialExpressionResult.create(
      study: @study, cluster_group: @study.cluster_groups.by_name('clusterA.txt'), matrix_file_id: matrix.id,
      annotation_name: 'disease', annotation_scope: 'study', observed_values: %w[none measles]
    )
  end

  teardown do
    OmniAuth.config.mock_auth[:google_oauth2] = nil
  end

  test 'access control enforced' do
    sign_in_and_update @user
    execute_http_request(:get, api_v1_report_path('studies'), user: @user)
    assert_equal 403, response.status

    sign_in_and_update @admin_user
    execute_http_request(:get, api_v1_report_path('studies'), user: @admin_user)
    assert_equal 200, response.status
  end

  test 'invalid report name rejected' do
    sign_in_and_update @admin_user
    execute_http_request(:get, api_v1_report_path('blahblah'), user: @admin_user)
    assert_equal 400, response.status
  end

  test 'can fetch study report' do
    sign_in_and_update @admin_user
    execute_http_request(:get, api_v1_report_path('studies'), user: @admin_user)
    assert_equal 200, response.status
    assert response.body.starts_with?("accession\tcreated_at\tcell_count")
  end

  test 'can fetch differential expression report' do
    sign_in_and_update @admin_user
    execute_http_request(:get, api_v1_report_path('differential_expression'), user: @admin_user)
    assert_equal 200, response.status
    assert response.body.starts_with?("accession\tcreated_at\tcluster_name\tannotation_identifier")
  end
end
