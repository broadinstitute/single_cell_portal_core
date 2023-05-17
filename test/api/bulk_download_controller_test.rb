require 'api_test_helper'
require 'test_helper'
require 'user_tokens_helper'
require 'bulk_download_helper'
require 'includes_helper'
require 'detached_helper'

class BulkDownloadControllerTest < ActionDispatch::IntegrationTest

  SYNTH_STUDY_FOLDER = 'mouse_brain' # use the mouse_Brain study as it has all file types including genomic

  before(:all) do
    @user = FactoryBot.create(:api_user, test_array: @@users_to_clean)
    @taxon = Taxon.find_or_create_by!(common_name: 'mouse_fake1',
                           scientific_name: 'Mus musculusfake1',
                           user: @user,
                           ncbi_taxid: 100901,
                           notes: 'fake mouse taxon 1 for testing')
    @genome_assembly = GenomeAssembly.find_or_create_by!(name: "GRCm38",
                                              alias: nil,
                                              release_date: '2012-01-09',
                                              accession: "GCA_000001635.2",
                                              taxon: @taxon)
    @genome_annotation = GenomeAnnotation.find_or_create_by!(name: 'Ensembl 94',
                                                  link: 'http://google.com/search?q=mouse',
                                                  index_link: 'http://google.com/search?q=mouse_index',
                                                  release_date: '2020-10-19',
                                                  genome_assembly: @genome_assembly)
    @basic_study = FactoryBot.create(:detached_study,
                                     name_prefix: 'Basic Cluster Study',
                                     public: false,
                                     user: @user,
                                     test_array: @@studies_to_clean)
    @basic_study_cluster_file = FactoryBot.create(:cluster_file,
                                                  name: 'clusterA.txt',
                                                  study: @basic_study,
                                                  upload_file_size: 100)

    @basic_study_metadata_file = FactoryBot.create(:metadata_file,
                                                   name: 'metadata.txt',
                                                   study: @basic_study,
                                                   upload_file_size: 200)

    @basic_study_expression_file = FactoryBot.create(:expression_file,
                                                   name: 'expression.txt',
                                                   taxon: @taxon,
                                                   expression_file_info: {
                                                     is_raw_counts: true,
                                                     units: 'raw counts',
                                                     library_preparation_protocol: 'Drop-seq',
                                                     biosample_input_type: 'Whole cell',
                                                     modality: 'Proteomic'
                                                   },
                                                   study: @basic_study,
                                                   upload_file_size: 300)

    @basic_study_fastq_file = FactoryBot.create(:study_file,
                                                  name: 'fastq.fastq',
                                                  file_type: 'Fastq',
                                                  taxon: @taxon,
                                                  study: @basic_study,
                                                  upload_file_size: 100)
    sign_in_and_update @user
    # empty strong params for getting auth codes
    @auth_code_params = { bulk_download: { file_ids: [], azul_files: {} } }
  end


  teardown do
    OmniAuth.config.mock_auth[:google_oauth2] = nil
    @basic_study.directory_listings.delete_all
  end

  after(:all) do
    @taxon.destroy
  end

  # should generate a config text file to pass to curl for bulk download
  test 'should generate curl config for bulk download' do
    study = @basic_study
    mock_query_not_detached [study] do
      files = study.study_files.by_type(['Expression Matrix', 'Metadata'])
      mock = generate_signed_urls_mock(files)
      FireCloudClient.stub :new, mock do
        execute_http_request(:post,
                             api_v1_bulk_download_auth_code_path,
                             request_payload: @auth_code_params,
                             user: @user)
        assert_response :success
        auth_code = json['auth_code']

        file_types = %w(Expression Metadata).join(',')
        execute_http_request(:get, api_v1_bulk_download_generate_curl_config_path(
          auth_code: auth_code, accessions: study.accession, file_types: file_types, directory: 'all')
        )
        assert_response :success
        config_file = json

        files.each do |file|
          filename = file.upload_file_name
          assert config_file.include?(filename), "Did not find URL for filename: #{filename}"
          output_path = file.bulk_download_pathname
          assert config_file.include?(output_path), "Did not correctly set output path for #{filename} to #{output_path}"
        end

        refute config_file.include?('clusterA.txt'), "Should not include cluster file, as it was not a requested type"

        # ensure bad/missing auth_token return 401
        invalid_auth_code = auth_code.to_i + 1
        execute_http_request(:get, api_v1_bulk_download_generate_curl_config_path(
          auth_code: invalid_auth_code, accessions: study.accession, file_types: file_types)
        )
        assert_response :unauthorized

        execute_http_request(:get, api_v1_bulk_download_generate_curl_config_path(accessions: study.accession, file_types: file_types))
        # response should fail with no auth_code, since auth code is required
        assert_response :unauthorized
      end
    end
  end

  test 'should return preview of bulk download files and total bytes' do
    study = @basic_study
    mock_query_not_detached [study] do
      execute_http_request(:get, api_v1_bulk_download_summary_path(accessions: study.accession), user: @user)
      assert_response :success

      expected_response = BulkDownloadService.get_download_info([@basic_study.accession])
      assert_equal expected_response.to_json, json.to_json
    end
  end

  test 'single-study bulk download should include all study files' do
    study = @basic_study
    mock_query_not_detached [study] do
      mock = Minitest::Mock.new
      @basic_study.study_files.each do |file|
        bucket_id = @basic_study.bucket_id
        file_location = file.bucket_location
        url = "https://www.googleapis.com/storage/v1/b/#{bucket_id}/#{file_location}"
        mock.expect :execute_gcloud_method, url, [:generate_signed_url, 0, bucket_id, file_location, Hash]
      end
      FireCloudClient.stub :new, mock do
        execute_http_request(:post,
                             api_v1_bulk_download_auth_code_path,
                             request_payload: @auth_code_params,
                             user: @user)
        assert_response :success
        auth_code = json['auth_code']

        execute_http_request(:get, api_v1_bulk_download_generate_curl_config_path(
          auth_code: auth_code, accessions: study.accession)
        )
        assert_response :success

        study.study_files.each do |study_file|
          assert json.include?(study_file.name), "Bulk download config did not include #{study_file.name}"
        end
      end
    end
  end

  test 'should honor directory parameter for single-study bulk download' do
    @files = {
      csv: [ "csv/file_1.csv" ],
      xlsx: [ "xlsx/file_2.xlsx" ]
    }
    study_files = @basic_study.study_files.to_a
    mock_query_not_detached [@basic_study] do
      # single directory test
      @files.each do |file_type, files|
        file_list = files.map do |file|
          { generation: (SecureRandom.rand * 100000).floor, name: file, size: 100 }.with_indifferent_access
        end
        directory = DirectoryListing.create!(study: @basic_study, file_type: file_type, name: file_type,
                                             files: file_list, sync_status: true)
        assert directory.persisted?
        execute_http_request(:post,
                             api_v1_bulk_download_auth_code_path,
                             request_payload: @auth_code_params,
                             user: @user)
        assert_response :success
        auth_code = json['auth_code']
        all_files = study_files + files
        mock = generate_signed_urls_mock(all_files, parent_study: @basic_study)
        FireCloudClient.stub :new, mock do
          execute_http_request(:get,
                               api_v1_bulk_download_generate_curl_config_path(
                                 auth_code: auth_code,
                                 accessions: [@basic_study.accession],
                                 directory: "#{file_type}--#{file_type}"
                               ))
          assert_response :success
          mock.verify
          files.each do |file|
            assert json.include? file
          end
        end
      end
      # all directories test
      execute_http_request(:post,
                           api_v1_bulk_download_auth_code_path,
                           request_payload: @auth_code_params,
                           user: @user)
      assert_response :success
      auth_code = json['auth_code']
      dir_files = @files.values.flatten
      all_files = study_files + dir_files
      all_dirs_mock = generate_signed_urls_mock(all_files, parent_study: @basic_study)
      FireCloudClient.stub :new, all_dirs_mock do
        execute_http_request(:get,
                             api_v1_bulk_download_generate_curl_config_path(
                               auth_code: auth_code,
                               accessions: [@basic_study.accession],
                               directory: 'all'
                             ))
        assert_response :success
        all_dirs_mock.verify
        all_files.each do |file|
          filename = file.try(:upload_file_name) || file
          assert json.include? filename
        end
      end
    end
  end

  test 'multi-study bulk download should exclude sequence data' do
    # negative test, ensure that multi-study bulk download excludes sequence data
    new_study = FactoryBot.create(:detached_study,
                                  name_prefix: 'Extra Study',
                                  public: false,
                                  user: @user,
                                  test_array: @@studies_to_clean)
    FactoryBot.create(:cluster_file,
                      name: 'cluster.txt',
                      study: new_study,
                      upload_file_size: 100)
    mock_query_not_detached [@basic_study, new_study] do
      execute_http_request(:post,
                           api_v1_bulk_download_auth_code_path,
                           request_payload: @auth_code_params,
                           user: @user)
      assert_response :success
      auth_code = json['auth_code']
      all_files = [
        @basic_study_expression_file, @basic_study_metadata_file, @basic_study_cluster_file, new_study.study_files.first
      ]
      mock = generate_signed_urls_mock(all_files)
      FireCloudClient.stub :new, mock do
        execute_http_request(:get, api_v1_bulk_download_generate_curl_config_path(
          auth_code: auth_code, accessions: [@basic_study.accession, new_study.accession])
        )
        assert_response :success
        excluded_file = @basic_study.study_files.by_type('Fastq').first
        refute json.include?(excluded_file.name), 'Bulk download config did not exclude external fastq link'
      end
    end
  end

  test 'bulk download should support a download_id and HCA files' do
    mock_query_not_detached [@basic_study] do
      hca_project_id = SecureRandom.uuid
      payload = {
        bulk_download: {
          file_ids: [@basic_study_metadata_file.id.to_s],
          azul_files: {
            FakeHCAStudy1: [
              {
                project_id: hca_project_id,
                name: 'hca_file1.tsv',
                count: 1,
                file_type: 'Project Manifest'
              }, {
                source: 'hca',
                count: 1,
                upload_file_size: 10.megabytes,
                file_format: 'loom',
                file_type: 'analysis_file',
                accession: 'FakeHCAStudy1',
                project_id: hca_project_id
              }
            ]
          }
        }
      }
      execute_http_request(:post,
                           api_v1_bulk_download_auth_code_path,
                           request_payload: payload,
                           user: @user)
      assert_response :success
      auth_code = json['auth_code']
      download_id = json['download_id']

      # mock response values
      mock_signed_url = "https://www.googleapis.com/storage/v1/b/#{@basic_study.bucket_id}/metadata.txt"
      mock_manifest_response = {
        Status: 302,
        Location: "https://service.azul.data.humancellatlas.org/manifest/files?catalog=dcp8&format=compact&filters=" \
                "%7B%22projectId%22%3A+%7B%22is%22%3A+%5B%22#{hca_project_id}%22%5D%7D%7D&objectKey=manifests%2F" \
                "#{SecureRandom.uuid}.tsv"
      }.with_indifferent_access

      mock_files_response = [
        {
          format: 'loom',
          name: 'SomeAnalysis.loom',
          size: 10.megabytes,
          url: "https://service.azul.data.humancellatlas.org/repository/files/#{SecureRandom.uuid}",
          projectShortname: 'FakeHCAStudy1',
          projectId: hca_project_id
        }.with_indifferent_access
      ]

      # mock all calls to external services, including Google Cloud Storage, HCA Azul, and Terra Data Repo
      gcs_mock = Minitest::Mock.new
      gcs_mock.expect :execute_gcloud_method, mock_signed_url,
                      [:generate_signed_url, 0, @basic_study.bucket_id, 'metadata.txt', { expires: 1.day.to_i }]
      azul_mock = Minitest::Mock.new
      azul_mock.expect :project_manifest_link, mock_manifest_response, [hca_project_id]
      azul_mock.expect :files, mock_files_response, [Hash]

      # stub all service clients to interpolate mocks
      FireCloudClient.stub :new, gcs_mock do
        ApplicationController.stub :hca_azul_client, azul_mock do
          # gotcha because we've stubbed Study.where in mock_query_not_detached and this wll cause
          # BulkDownloadController.load_study_files to return the wrong studies, so we have to override that here
          metadata_id = @basic_study_metadata_file.id
          Api::V1::BulkDownloadController.stub :load_study_files, StudyFile.where(id: metadata_id) do
            execute_http_request(:get, api_v1_bulk_download_generate_curl_config_path(
              auth_code: auth_code, download_id: download_id))
            assert_response :success
            config_file = json
            gcs_mock.verify
            azul_mock.verify

            expected_manifest_config = "url=\"#{mock_manifest_response[:Location]}\"\noutput=\"FakeHCAStudy1/hca_file1.tsv\""
            assert config_file.include?("#{@basic_study.accession}/metadata/metadata.txt"), 'did not include SCP metadata file'
            assert config_file.include?(expected_manifest_config), 'did not include correct HCA manifest file or output path'
            assert config_file.include?("output=\"FakeHCAStudy1/SomeAnalysis.loom\"")
          end
        end
      end
    end
  end

  test 'should ignore empty/missing Azul entries' do
    mock_query_not_detached [@basic_study] do
      hca_project_id = SecureRandom.uuid
      payload = {
        bulk_download: {
          file_ids: [@basic_study_metadata_file.id.to_s],
          azul_files: {
            FakeHCAStudy1: [
              {
                source: 'hca',
                count: 1,
                upload_file_size: 10.megabytes,
                file_format: 'loom',
                file_type: 'analysis_file',
                accession: 'FakeHCAStudy1',
                project_id: hca_project_id
              }
            ],
            FakeHcaStudy2: []
          }
        }
      }
      execute_http_request(:post,
                           api_v1_bulk_download_auth_code_path,
                           request_payload: payload,
                           user: @user)
      assert_response :success

      download_id = json['download_id']
      download_request = DownloadRequest.find(download_id)
      assert download_request.present?
      azul_files = download_request.azul_files_as_hash
      assert azul_files.keys.include?('FakeHCAStudy1')
      assert_not azul_files.keys.include?('FakeHCAStudy2')
    end
  end

  test 'should complete download request for HCA projects w/o analysis/sequence files' do
    hca_project_id = SecureRandom.uuid
    payload = {
      bulk_download: {
        file_ids: [],
        azul_files: {
          FakeHCAStudy1: [
            {
              count: 1,
              upload_file_size: 1.megabyte,
              file_type: 'Project Manifest',
              project_id: hca_project_id,
              name: 'FakeHCAStudy1.tsv'
            }
          ]
        }
      }
    }
    execute_http_request(:post,
                         api_v1_bulk_download_auth_code_path,
                         request_payload: payload,
                         user: @user)
    assert_response :success
    download_id = json['download_id']
    auth_code = json['auth_code']
    mock = Minitest::Mock.new
    manifest_info = {
      Status: 302,
      Location: 'https://service.azul.data.humancellatlas.org/manifest/files?catalog=dcp12&format=compact&' \
                "filters=%7B%22projectId%22%3A+%7B%22is%22%3A+%5B%22#{hca_project_id}%22%5D%7D%7D&objectKey=" \
                'manifests%2FFakeHCAStudy1.tsv'
    }.with_indifferent_access
    mock.expect :project_manifest_link, manifest_info, [hca_project_id]
    ApplicationController.stub :hca_azul_client, mock do
      execute_http_request(:get,
                           api_v1_bulk_download_generate_curl_config_path(
                             auth_code: auth_code, download_id: download_id
                           ),
                           user: @user)
      assert_response :success
      mock.verify
      assert json.include? manifest_info[:Location]
    end
  end

  test 'should complete download request for HCA project' do
    hca_project_id = SecureRandom.uuid
    payload = {
      bulk_download: {
        file_ids: [],
        azul_files: {
          FakeHCAStudy1: [
            {
              count: 1,
              upload_file_size: 1.megabyte,
              file_type: 'Project Manifest',
              project_id: hca_project_id,
              name: 'Fa..keHCAStudy1.tsv'
            }
          ]
        }
      }
    }
    execute_http_request(:post,
                         api_v1_bulk_download_auth_code_path,
                         request_payload: payload,
                         user: @user)
    assert_response :success
    download_id = json['download_id']
    auth_code = json['auth_code']
    mock = Minitest::Mock.new
    manifest_info = {
      Status: 302,
      Location: 'https://service.azul.data.humancellatlas.org/manifest/files?catalog=dcp12&format=compact&' \
                "filters=%7B%22projectId%22%3A+%7B%22is%22%3A+%5B%22#{hca_project_id}%22%5D%7D%7D&objectKey=" \
                'manifests%2FFakeHCAStudy1.tsv'
    }.with_indifferent_access
    mock.expect :project_manifest_link, manifest_info, [hca_project_id]
    ApplicationController.stub :hca_azul_client, mock do
      execute_http_request(:get,
                           api_v1_bulk_download_generate_curl_config_path(
                             auth_code: auth_code, download_id: download_id
                           ),
                           user: @user)
      assert_response :success
      mock.verify
      assert json.include? manifest_info[:Location]
    end
  end

  test 'should extract accessions from parameters' do
    study = FactoryBot.create(:detached_study,
                              name_prefix: 'Accession Test',
                              public: true,
                              user: @user,
                              test_array: @@studies_to_clean)
    mock_query_not_detached [@basic_study, study] do
      accessions = [@basic_study.accession, 'FakeHCAProject', study.accession, 'AnotherFakeHCAProject']
      scp_accessions = Api::V1::BulkDownloadController.find_matching_accessions(accessions)
      hca_accessions = Api::V1::BulkDownloadController.extract_hca_accessions(accessions)
      assert_equal [@basic_study.accession, study.accession].sort, scp_accessions.sort
      assert_equal %w[FakeHCAProject AnotherFakeHCAProject].sort, hca_accessions.sort
    end
  end
end
