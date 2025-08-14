require 'api_test_helper'
require 'user_helper'
require 'test_helper'
require 'includes_helper'
require 'detached_helper'

class ApiSiteControllerTest < ActionDispatch::IntegrationTest

  before(:all) do
    @user = FactoryBot.create(:admin_user, test_array: @@users_to_clean)
    @other_user = FactoryBot.create(:api_user, test_array: @@users_to_clean)
    @study = FactoryBot.create(:detached_study,
                               name_prefix: 'API Site Controller Study',
                               public: true,
                               user: @user,
                               test_array: @@studies_to_clean)
    @cluster_file = FactoryBot.create(:cluster_file,
                                      study: @study,
                                      name: 'cluster.txt',
                                      status: 'uploaded',
                                      generation: '123456789',
                                      upload_file_size: 1.megabyte,
                                      parse_status: 'parsed')

    StudyShare.create!(email: 'fake.email@gmail.com', permission: 'Reviewer', study: @study)
    StudyFile.create(study: @study, name: 'SRA Study for housing fastq data', description: 'SRA Study for housing fastq data',
                     file_type: 'Fastq', status: 'uploaded', human_fastq_url: 'https://www.ncbi.nlm.nih.gov/sra/ERX4159348[accn]')
    DirectoryListing.create!(name: 'csvs', file_type: 'csv', files: [{name: 'foo.csv', size: 100, generation: '12345'}],
                             sync_status: true, study: @study)
    StudyFileBundle.create!(bundle_type: 'BAM',
                            original_file_list: [
                              { 'name' => 'sample_1.bam', 'file_type' => 'BAM' },
                              { 'name' => 'sample_1.bam.bai', 'file_type' => 'BAM Index' }
                            ],
                            study: @study)
    @study.external_resources.create(url: 'https://singlecell.broadinstitute.org', title: 'SCP',
                                     description: 'Link to Single Cell Portal')
  end

  teardown do
    DifferentialExpressionResult.delete_all
    OmniAuth.config.mock_auth[:google_oauth2] = nil
    reset_user_tokens
    @study.update(public: true)
  end

  test 'should get all studies' do
    sign_in_and_update @user
    viewable = Study.viewable(@user)
    execute_http_request(:get, api_v1_site_studies_path)
    assert_response :success
    assert_equal json.size, viewable.size, "Did not find correct number of studies, expected #{viewable.size} or more but found #{json.size}"
  end

  test 'should get one study' do
    mock_not_detached @study, :find_by do
      sign_in_and_update @user
      expected_files = @study.study_files.downloadable.count
      expected_resources = @study.external_resources.count
      execute_http_request(:get, api_v1_site_study_view_path(accession: @study.accession))
      assert_response :success
      assert json['study_files'].size == expected_files,
             "Did not find correct number of files, expected #{expected_files} but found #{json['study_files'].size}"
      assert json['external_resources'].size == expected_resources,
             "Did not find correct number of resource links, expected #{expected_resources} but found #{json['external_resources'].size}"

      # ensure access restrictions are in place
      @study.update(public: false)
      sign_in_and_update @other_user
      execute_http_request(:get, api_v1_site_study_view_path(accession: @study.accession), user: @other_user)
      assert_response 403
    end
  end

  test 'should respond 410 on detached study' do
    sign_in_and_update @user
    file = @study.study_files.first

    execute_http_request(:get, api_v1_site_study_download_data_path(accession: @study.accession, filename: file.upload_file_name))
    assert_response 410,
                    "Did not provide correct response code when downloading file from detached study, expected 401 but found #{response.code}"
  end

  test 'should download file' do
    mock_not_detached @study, :find_by do
      sign_in_and_update @user
      file = @study.study_files.first
      mock_url = "https://storage.googleapis.com/#{@study.bucket_id}/#{file.upload_file_name}"
      mock = Minitest::Mock.new
      mock.expect :signed_url_for_bucket_file, mock_url, [@study.bucket_id, file.bucket_location], expires: Integer
      StorageService.stub :load_client, mock do
        execute_http_request(:get, api_v1_site_study_download_data_path(accession: @study.accession, filename: file.upload_file_name))
        assert_response 302, "Did not correctly redirect to file: #{response.code}"

        # since this is an external redirect, we cannot call follow_redirect! but instead have to get the location header
        signed_url = response.headers['Location']
        assert signed_url.include?(file.upload_file_name), "Redirect url does not point at requested file"

        # now assert 401 if user isn't signed in
        # we can mimic the sign-out by unsetting the user object so that no Authorization: Bearer token is passed with the request
        @user = nil
        execute_http_request(:get, api_v1_site_study_download_data_path(accession: @study.accession, filename: file.upload_file_name))
        assert_response 401, "Did not correctly respond 401 if user is not signed in: #{response.code}"

        # ensure private downloads respect access restriction
        @study.update(public: false)
        sign_in_and_update @other_user
        execute_http_request(:get, api_v1_site_study_download_data_path(accession: @study.accession, filename: file.upload_file_name),
                             user: @other_user)
        assert_response 403
      end
    end
  end

  test 'should get stream options for file' do
    mock_not_detached @study, :find_by do
      sign_in_and_update @user
      file = @study.study_files.first
      mock_url = "https://www.googleapis.com/storage/v1/b/#{@study.bucket_id}/o/#{file.upload_file_name}?alt=media"
      mock = Minitest::Mock.new
      mock.expect :api_url_for_bucket_file, mock_url, [@study.bucket_id, file.bucket_location]
      @study.stub :storage_provider, mock do
        execute_http_request(:get, api_v1_site_study_stream_data_path(accession: @study.accession, filename: file.upload_file_name))
        assert_response :success
        assert_equal file.upload_file_name, json['filename'],
                     "Incorrect file was returned; #{file.upload_file_name} != #{json['filename']}"
        assert json['url'].include?(file.upload_file_name),
               "Url does not contain correct file: #{file.upload_file_name} is not in #{json['url']}"

        # assert 401 if no user is signed in
        @user = nil
        execute_http_request(:get, api_v1_site_study_stream_data_path(accession: @study.accession, filename: file.upload_file_name))
        assert_response 401, "Did not correctly respond 401 if user is not signed in: #{response.code}"

        @study.update(public: false)
        sign_in_and_update @other_user
        execute_http_request(:get, api_v1_site_study_stream_data_path(accession: @study.accession, filename: file.upload_file_name),
                             user: @other_user)
        assert_response 403
      end
    end
  end

  test 'external sequence data should return correct download link' do
    mock_not_detached @study, :find_by do
      sign_in_and_update @user
      external_sequence_file = @study.study_files.by_type('Fastq').first
      execute_http_request(:get, api_v1_site_study_view_path(accession: @study.accession))
      assert_response :success
      external_entry = json['study_files'].detect {|file| file['name'] == external_sequence_file.name}
      assert_equal external_sequence_file.human_fastq_url, external_entry['download_url'],
                   "Did not return correct download url for external fastq; #{external_entry['download_url']} != #{external_sequence_file.human_fastq_url}"
    end
  end

  test 'should submit differential expression request' do
    user = FactoryBot.create(:api_user, test_array: @@users_to_clean)
    study = FactoryBot.create(:detached_study, name_prefix: 'DiffExp Submit Test', user:, test_array: @@studies_to_clean)
    cells = %w[A B C D E F G]
    coordinates = 1.upto(7).to_a
    species = %w[dog cat dog dog cat cat cat]
    cell_types = ['B cell', 'T cell', 'B cell', 'T cell', 'T cell', 'B cell', 'B cell']
    custom_cell_types = ['Custom 1', 'Custom 2', 'Custom 1', 'Custom 2', 'Custom 1', 'Custom 2', 'Custom 2']
    raw_matrix = FactoryBot.create(
      :expression_file, name: 'raw.txt', study:, expression_file_info: {
      is_raw_counts: true, units: 'raw counts', library_preparation_protocol: 'Drop-seq',
      biosample_input_type: 'Whole cell', modality: 'Proteomic' }
    )
    cluster_file = FactoryBot.create(:cluster_file,
                                     name: 'umap',
                                     study:,
                                     cell_input: { x: coordinates, y: coordinates, cells: })
    cluster_group = ClusterGroup.find_by(study:, study_file: cluster_file)

    FactoryBot.create(
      :metadata_file, name: 'metadata.txt', study:, cell_input: cells, annotation_input: [
        { name: 'species', type: 'group', values: species },
        { name: 'cell_type__ontology_label', type: 'group', values: cell_types },
        { name: 'cell_type__custom', type: 'group', values: custom_cell_types }]
    )

    DifferentialExpressionResult.create(
      study:, cluster_group:, annotation_name: 'species', annotation_scope: 'study', matrix_file_id: raw_matrix.id,
      pairwise_comparisons: { dog: %w[cat]}
    )
    mock_not_detached study, :find_by do
      sign_in_and_update user

      # stub :raw_matrix_for_cluster_cells to avoid having to create cell arrays manually
      ClusterVizService.stub :raw_matrix_for_cluster_cells, raw_matrix do
        valid_params = [
          {
            cluster_name: 'umap', annotation_name: 'cell_type__ontology_label',
            annotation_scope: 'study', de_type: 'rest'
          },
          {
            cluster_name: 'umap', annotation_name: 'cell_type__ontology_label',
            annotation_scope: 'study', de_type: 'pairwise', group1: 'B cell', group2: 'T cell'
          }
        ]
        # test normal submission
        valid_params.each do |job_params|
          job_mock = Minitest::Mock.new
          job_mock.expect :push_remote_and_launch_ingest, nil
          delay_mock = Minitest::Mock.new
          delay_mock.expect :delay, job_mock
          IngestJob.stub :new, delay_mock do
            execute_http_request(:post,
                                 api_v1_site_study_submit_differential_expression_path(accession: study.accession),
                                 request_payload: job_params,
                                 user:)
            assert_response 204
            delay_mock.verify
          end
        end
        # check for existing results
        existing_params = {
          cluster_name: 'umap', annotation_name: 'species',
          annotation_scope: 'study', de_type: 'pairwise', group1: 'dog', group2: 'cat'
        }
        execute_http_request(:post,
                             api_v1_site_study_submit_differential_expression_path(accession: study.accession),
                             request_payload: existing_params,
                             user:)
        assert_response 409
        # request parameter validations
        execute_http_request(:post,
                             api_v1_site_study_submit_differential_expression_path(accession: study.accession),
                             request_payload: { cluster_name: 'foo'},
                             user:)
        assert_response :not_found
        execute_http_request(:post,
                             api_v1_site_study_submit_differential_expression_path(accession: study.accession),
                             request_payload: {
                               cluster_name: 'umap', annotation_name: 'foo', annotation_scope: 'study'
                             },
                             user:)
        assert_response :not_found

        execute_http_request(:post,
                             api_v1_site_study_submit_differential_expression_path(accession: study.accession),
                             request_payload: {
                               cluster_name: 'umap', annotation_name: 'cell_type__ontology_label',
                               annotation_scope: 'study', de_type: 'foo'
                             },
                             user:)
        assert_response 422
        execute_http_request(:post,
                             api_v1_site_study_submit_differential_expression_path(accession: study.accession),
                             request_payload: {
                               cluster_name: 'umap', annotation_name: 'cell_type__ontology_label',
                               annotation_scope: 'study', de_type: 'pairwise'
                             },
                             user:)
        assert_response 422
        # check rate limit
        user.update(weekly_de_quota: DifferentialExpressionService::DEFAULT_USER_QUOTA)
        execute_http_request(:post,
                             api_v1_site_study_submit_differential_expression_path(accession: study.accession),
                             request_payload: {
                               cluster_name: 'umap', annotation_name: 'cell_type__ontology_label',
                               annotation_scope: 'study', de_type: 'pairwise', group1: 'T cell', group2: 'B cell'
                             },
                             user:)
        assert_response 429
        # check for author results
        study.differential_expression_results.delete_all
        de_file = FactoryBot.create(:differential_expression_file,
                                    study:,
                                    name: 'user_de.txt',
                                    annotation_name: 'cell_type__custom',
                                    annotation_scope: 'study',
                                    cluster_group:,
                                    computational_method: 'custom'
        )
        author_result = DifferentialExpressionResult.create(
          study:, cluster_group:, annotation_name: 'cell_type__custom', annotation_scope: 'study',
          study_file: de_file, is_author_de: true, one_vs_rest_comparisons: ['Custom 1', 'Custom 2']
        )
        assert author_result.persisted?
        params = {
          cluster_name: 'umap', annotation_name: 'cell_type__ontology_label',
          annotation_scope: 'study', de_type: 'rest'
        }
        execute_http_request(:post,
                             api_v1_site_study_submit_differential_expression_path(accession: study.accession),
                             request_payload: params,
                             user:)
        assert_response :forbidden
        assert json['error'].starts_with? 'User requests are disabled'
      end
    end
  end
end
