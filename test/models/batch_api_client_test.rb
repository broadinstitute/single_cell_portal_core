# frozen_string_literal: true
require 'test_helper'
class BatchApiClientTest
  before(:all) do
    @client = ApplicationController.batch_api_client
    @user = FactoryBot.create(:user, test_array: @@users_to_clean)
    @study = FactoryBot.create(:detached_study,
                               name_prefix: 'Batch Client Test',
                               user: @user,
                               test_array: @@studies_to_clean)

    @expression_matrix = FactoryBot.create(:study_file, name: 'dense.txt', file_type: 'Expression Matrix', study: @study)

    @expression_matrix.build_expression_file_info(is_raw_counts: true, units: 'raw counts',
                                                  library_preparation_protocol: 'MARS-seq',
                                                  modality: 'Transcriptomic: unbiased',
                                                  biosample_input_type: 'Whole cell')
    @expression_matrix.save!
    @cluster_file = FactoryBot.create(:cluster_file,
                                      name: 'cluster.txt', study: @study,
                                      cell_input: {
                                        x: [1, 4, 6],
                                        y: [7, 5, 3],
                                        z: [2, 8, 9],
                                        cells: %w[A B C]
                                      },
                                      x_axis_label: 'PCA 1',
                                      y_axis_label: 'PCA 2',
                                      z_axis_label: 'PCA 3',
                                      cluster_type: '3d',
                                      x_axis_min: -1,
                                      x_axis_max: 1,
                                      y_axis_min: -2,
                                      y_axis_max: 2,
                                      z_axis_min: -3,
                                      z_axis_max: 3,
                                      annotation_input: [
                                        { name: 'Category', type: 'group', values: %w[bar bar baz] },
                                        { name: 'Intensity', type: 'numeric', values: [1.1, 2.2, 3.3] }
                                      ])
    @compute_region = LifeSciencesApiClient::DEFAULT_COMPUTE_REGION
  end

  test 'should instantiate client and assign attributes' do
    client = BatchApiClient.new
    assert client.project.present?
    assert client.service_account_credentials.present?
    assert client.service.present?
  end

  test 'should get client issuer' do
    issuer = @client.issuer
    assert issuer.match(/gserviceaccount\.com$/)
  end

  test 'should get project and location' do
    location = @client.project_location
    assert location.include?(@client.project)
    assert location.include?(BatchApiClient::DEFAULT_COMPUTE_REGION)
  end

  test 'should list pipelines' do
    pipelines = @client.list_pipelines
    skip 'could not find any pipelines' if pipelines.operations.blank?
    assert pipelines.present?
    assert pipelines.operations.any?
  end
end
