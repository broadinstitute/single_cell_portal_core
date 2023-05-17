require 'integration_test_helper'
require 'api_test_helper'
require 'user_tokens_helper'
require 'big_query_helper'
require 'test_helper'
require 'includes_helper'
require 'detached_helper'

class StudyValidationTest < ActionDispatch::IntegrationTest

  before(:all) do
    # make sure all studies/users have been removed as dangling references can sometimes cause false negatives/failures
    StudyCleanupTools.destroy_all_studies_and_workspaces
    User.destroy_all
    @user = FactoryBot.create(:admin_user, test_array: @@users_to_clean)
    @sharing_user = FactoryBot.create(:user, test_array: @@users_to_clean)
    @random_seed = SecureRandom.uuid
    @study = FactoryBot.create(:study,
                               name_prefix: 'Main Validation Study',
                               public: true,
                               user: @user,
                               test_array: @@studies_to_clean,
                               predefined_file_types: %w[cluster metadata expression])
  end

  setup do
    auth_as_user @user
    sign_in @user
    @user.update_last_access_at!
    @user.reload
  end

  teardown do
    OmniAuth.config.mock_auth[:google_oauth2] = nil
    reset_user_tokens
    @study.update(public: true)
  end

  after(:all) do
    Study.where(name: /#{@random_seed}/).map(&:destroy_and_remove_workspace)
  end

  # check that file header/format checks still function properly
  test 'should fail all ingest pipeline parse jobs' do
    study_name = "Validation Ingest Pipeline Parse Failure Study #{@random_seed}"
    study_params = {
      study: {
        name: study_name,
        user_id: @user.id
      }
    }
    post studies_path, params: study_params
    follow_redirect!
    assert_response 200, "Did not redirect to upload successfully"
    study = Study.find_by(name: study_name)
    assert study.present?, "Study did not successfully save"

    example_files = {
      metadata_breaking_convention: {
        name: 'metadata_example2.txt'
      },
      cluster: {
        name: 'cluster_bad.txt'
      },
      expression: {
        name: 'expression_matrix_example_bad.txt'
      }
    }

    ## upload files

    # good metadata file, but falsely claiming to use the metadata_convention
    file_params = { study_file: { file_type: 'Metadata', study_id: study.id.to_s, use_metadata_convention: true } }
    perform_study_file_upload('metadata_example2.txt', file_params, study.id)
    assert_response 200, "Metadata upload failed: #{@response.code}"
    metadata_file = study.metadata_file
    example_files[:metadata_breaking_convention][:object] = metadata_file
    example_files[:metadata_breaking_convention][:cache_location] = metadata_file.parse_fail_bucket_location
    assert example_files[:metadata_breaking_convention][:object].present?,
           "Metadata failed to associate, found no file: #{example_files[:metadata_breaking_convention][:object].present?}"

    # metadata file that should fail validation because we already have one
    file_params = { study_file: { file_type: 'Metadata', study_id: study.id.to_s } }
    perform_study_file_upload('metadata_bad.txt', file_params, study.id)
    assert_response 422, "Metadata did not fail validation: #{@response.code}"

    # bad cluster
    file_params = { study_file: { name: 'Bad Test Cluster 1', file_type: 'Cluster', study_id: study.id.to_s } }
    perform_study_file_upload('cluster_bad.txt', file_params, study.id)
    assert_response 200, "Cluster 1 upload failed: #{@response.code}"
    assert_equal 1, study.cluster_ordinations_files.size,
                 "Cluster 1 failed to associate, found #{study.cluster_ordinations_files.size} files"
    cluster_file = study.cluster_ordinations_files.first
    example_files[:cluster][:object] = cluster_file
    example_files[:cluster][:cache_location] = cluster_file.parse_fail_bucket_location

    # bad expression matrix (duplicate gene)
    file_params = { study_file: { file_type: 'Expression Matrix', study_id: study.id.to_s } }
    perform_study_file_upload('expression_matrix_example_bad.txt', file_params, study.id)
    assert_response 200, "Expression matrix upload failed: #{@response.code}"
    assert_equal 1, study.expression_matrix_files.size,
                 "Expression matrix failed to associate, found #{study.expression_matrix_files.size} files"
    expression_matrix = study.expression_matrix_files.first
    example_files[:expression][:object] = expression_matrix
    example_files[:expression][:cache_location] = expression_matrix.parse_fail_bucket_location


    ## request parse
    example_files.each do |file_type,file|
      puts "Requesting parse for file \"#{file[:name]}\"."
      assert_equal 'unparsed', file[:object].parse_status, "Incorrect parse_status for #{file[:name]}"
      initiate_study_file_parse(file[:name], study.id)
      assert_response 200, "#{file_type} parse job failed to start: #{@response.code}"
    end

    seconds_slept = 60
    sleep seconds_slept
    sleep_increment = 15
    max_seconds_to_sleep = 300
    until ( example_files.values.all? { |e| ['parsed', 'failed'].include? e[:object].parse_status } ) do
      puts "After #{seconds_slept} seconds, " + (example_files.values.map { |e| "#{e[:name]} is #{e[:object].parse_status}"}).join(", ") + '.'
      if seconds_slept >= max_seconds_to_sleep
        raise "Even after #{seconds_slept} seconds, not all files have been parsed."
      end
      sleep(sleep_increment)
      seconds_slept += sleep_increment
      example_files.values.each do |e|
        e[:object].reload
      end
    end
    puts "After #{seconds_slept} seconds, " + (example_files.values.map { |e| "#{e[:name]} is #{e[:object].parse_status}"}).join(", ") + '.'

    study.reload

    example_files.values.each do |e|
      e[:object].reload # address potential race condition between parse_status setting to 'failed' and DeleteQueueJob executing
      assert_equal 'failed', e[:object].parse_status, "Incorrect parse_status for #{e[:name]}"
      # check that file is cached in parse_logs/:id folder in the study bucket
      cached_file = ApplicationController.firecloud_client.execute_gcloud_method(:get_workspace_file, 0, study.bucket_id, e[:cache_location])
      assert cached_file.present?, "Did not find cached file at #{e[:cache_location]} in #{study.bucket_id}"
    end

    assert_equal 0, study.cell_metadata.size
    assert_equal 0, study.genes.size
    assert_equal 0, study.cluster_groups.size
    assert_equal 0, study.cluster_ordinations_files.size
  end

  test 'should prevent changing firecloud attributes' do
    study = FactoryBot.create(:detached_study,
                              user: @user,
                              name_prefix: 'Validation FireCloud Attribute Test',
                              test_array: @@studies_to_clean)
    workspace_name = study.firecloud_workspace
    # stub find/detached so that we can simulate a full study w/o overhead of creating workspace
    mock_not_detached study, :find do
      # test update and expected error messages
      update_params = {
        study: {
          firecloud_workspace: 'this-is-different',
          firecloud_project: 'not-the-same'
        }
      }
      patch study_path(study.id), params: update_params
      assert_select 'li#study_error_firecloud_project', 'Firecloud project cannot be changed once initialized.'
      assert_select 'li#study_error_firecloud_workspace', 'Firecloud workspace cannot be changed once initialized.'
      # reload study and assert values are unchange
      study.reload
      assert_equal FireCloudClient::PORTAL_NAMESPACE, study.firecloud_project,
                   "FireCloud project was not correct, expected #{FireCloudClient::PORTAL_NAMESPACE} but found #{study.firecloud_project}"
      assert_equal workspace_name, study.firecloud_workspace,
                   "FireCloud workspace was not correct, expected '#{workspace_name}' but found '#{study.firecloud_workspace}'"
    end
  end

  test 'should disable downloads for reviewers' do
    study = FactoryBot.create(:detached_study,
                              user: @user,
                              name_prefix: 'Validation Reviewer Share',
                              public: false,
                              test_array: @@studies_to_clean)

    StudyShare.create!(email: @sharing_user.email, permission: 'Reviewer', study: study,
                       firecloud_project: study.firecloud_project, firecloud_workspace: study.firecloud_workspace)
    # enable downloads by unsetting 'detached'
    study.build_study_detail(full_description: '')
    study.save
    mock_not_detached study, :find_by do
      assert study.study_shares.size == 1,
             "Did not successfully create study_share, found #{study.study_shares.size} shares"
      reviewer_email = study.study_shares.reviewers.first
      assert reviewer_email == @sharing_user.email,
             "Did not grant reviewer permission to #{@sharing_user.email}, reviewers: #{reviewer_email}"


      # load private study and validate reviewer can see study but not download data
      sign_out @user
      auth_as_user(@sharing_user)
      sign_in @sharing_user
      get view_study_path(accession: study.accession, study_name: study.url_safe_name)
      assert controller.current_user == @sharing_user,
             "Did not successfully authenticate as sharing user, current_user is #{controller.current_user.email}"
      assert_select "h1.study-lead", true, "Did not successfully load study page for #{study.name}"
      assert_select 'li#study-download-nav' do |element|
        assert element.attr('class').to_str.include?('disabled'),
               "Did not disable downloads tab for reviewer: '#{element.attr('class')}'"
      end

      # ensure direct call to download is still disabled
      get download_private_file_path(accession: study.accession, study_name: study.url_safe_name, filename: 'mock_study_doc_upload.txt')
      follow_redirect!
      assert_equal view_study_path(accession: study.accession, study_name: study.url_safe_name), path,
                   "Did not block download and redirect to study page, current path is #{path}"
    end
  end

  test 'should redirect for detached studies' do
    study = FactoryBot.create(:detached_study,
                              user: @user,
                              name_prefix: 'Detached Redirect Test',
                              test_array: @@studies_to_clean)
    get download_file_path(accession: study.accession, study_name: study.url_safe_name, filename: 'file.txt')
    assert_response 302,
                    "Did not attempt to redirect on a download from a detached study, expected 302 but found #{response.code}"
  end

  # ensure data removal from BQ on metadata delete
  test 'should delete data from bigquery' do
    study = FactoryBot.create(:detached_study,
                              user: @user,
                              name_prefix: 'Validation BQ Delete Study',
                              public: false,
                              test_array: @@studies_to_clean)
    metadata_file = FactoryBot.create(:metadata_file,
                                      study:,
                                      name: 'convention.metadata.txt',
                                      use_metadata_convention: true,
                                      generation: '123456789',
                                      status: 'uploaded')
    seed_example_bq_data(study)
    mock_not_detached study, :find_by do
      initial_bq_row_count = get_bq_row_count(study)
      assert initial_bq_row_count > 0, "wrong number of BQ rows found to test deletion capability"

      mock = Minitest::Mock.new
      mock.expect :services_available?, true, [String, String]
      mock.expect :execute_gcloud_method,
                  Google::Cloud::Storage::File.new,
                  [:get_workspace_file, Integer, String, String]
      mock.expect :execute_gcloud_method, true, [:delete_workspace_file, Integer, String, String]
      ApplicationController.stub :firecloud_client, mock do
        # request delete
        puts 'Requesting delete for metadata file'
        delete api_v1_study_study_file_path(study_id: study.id, id: metadata_file.id),
               as: :json, headers: { Authorization: "Bearer #{@user.api_access_token['access_token']}" }
        assert_response 204, 'Did not correctly respond 204 to delete request'
        seconds_slept = 0
        sleep_increment = 10
        max_seconds_to_sleep = 60
        while (bq_row_count = get_bq_row_count(study)) != 0
          puts "#{seconds_slept} seconds after requesting file deletion, bq_row_count is #{bq_row_count}."
          if seconds_slept >= max_seconds_to_sleep
            raise "Even #{seconds_slept} seconds after requesting file deletion, not all records have been deleted from bigquery."
          end
          sleep(sleep_increment)
          seconds_slept += sleep_increment
        end
        puts "#{seconds_slept} seconds after requesting file deletion, bq_row_count is #{bq_row_count}."
        assert get_bq_row_count(study) == 0
        mock.verify
      end
    end
  end

  test 'should allow files with spaces in names' do
    filename = "12_MB_file_with_space_in_filename 2.txt"
    sanitized_filename = filename.gsub(CarrierWave::SanitizedFile.sanitize_regexp, '_')
    file_params = { study_file: { file_type: 'Expression Matrix', study_id: @study.id.to_s, name: sanitized_filename } }
    exp_matrix = File.open(Rails.root.join('test', 'test_data', filename))
    perform_chunked_study_file_upload(filename, file_params, @study.id)
    assert_response 200, "Expression upload failed: #{@response.code}"
    @study.reload
    study_file = @study.study_files.detect { |file| file.name == sanitized_filename }
    assert_not study_file.nil?, 'Did not find newly uploaded expression matrix'
    assert_equal exp_matrix.size, study_file.upload_file_size,
                 "File sizes do not match; #{exp_matrix.size} != #{study_file.upload_file_size}"

    # clean up
    exp_matrix.close
    study_file.destroy
  end

  test 'should sanitize filenames with special characters' do
    filename = 'mock_study_doc_upload(1).txt'
    # Carrierwave uses CarrierWave::SanitizedFile.sanitize_regexp to replace non-word characters with underscores
    sanitized_filename = filename.gsub(CarrierWave::SanitizedFile.sanitize_regexp, '_')
    file_params = { study_file: { file_type: 'Documentation', study_id: @study.id.to_s } }
    perform_study_file_upload(filename, file_params, @study.id)
    assert_response 200, "README failed: #{@response.code}"
    @study.reload
    study_file = @study.study_files.detect { |file| file.upload_file_name == sanitized_filename }
    assert_not study_file.nil?, 'Did not find newly uploaded README with sanitized filename'

    # clean up
    study_file.destroy
  end

  # validates that additional expression matrices with unique cells can be ingested to a study that already has a
  # metadata file and at least one other expression matrix
  test 'should validate unique cells for expression matrices' do
    new_matrix = 'expression_matrix_example_2.txt'
    file_params = { study_file: { file_type: 'Expression Matrix', study_id: @study.id.to_s } }
    perform_study_file_upload(new_matrix, file_params, @study.id)
    assert_response 200, "Expression matrix upload failed: #{@response.code}"
    uploaded_matrix = @study.expression_matrix_files.detect { |file| file.upload_file_name == new_matrix }
    assert uploaded_matrix.present?, "Did not find newly uploaded matrix #{new_matrix}"
    puts "Requesting parse for file \"#{uploaded_matrix.upload_file_name}\"."
    assert_equal 'unparsed', uploaded_matrix.parse_status, "Incorrect parse_status for #{new_matrix}"
    initiate_study_file_parse(uploaded_matrix.upload_file_name, @study.id)
    assert_response 200, "#{new_matrix} parse job failed to start: #{@response.code}"

    seconds_slept = 60
    puts "Parse initiated for #{new_matrix}, polling for completion"
    sleep seconds_slept
    sleep_increment = 15
    max_seconds_to_sleep = 300
    until  ['parsed', 'failed'].include? uploaded_matrix.parse_status  do
      puts "After #{seconds_slept} seconds, #{new_matrix} is #{uploaded_matrix.parse_status}."
      if seconds_slept >= max_seconds_to_sleep
        raise "Sleep timeout after #{seconds_slept} seconds when waiting for parse of \"#{new_matrix}\"."
      end
      sleep(sleep_increment)
      seconds_slept += sleep_increment
      assert_not uploaded_matrix.queued_for_deletion, "parsing #{new_matrix} failed, and is queued for deletion"
      uploaded_matrix.reload
    end
    puts "After #{seconds_slept} seconds, #{new_matrix} is #{uploaded_matrix.parse_status}."
  end

  # ensure unauthorized users cannot edit other studies
  test 'should enforce access restrictions on editing studies' do
    auth_as_user(@user)
    sign_in @user
    patch study_path(@study), params: { study: { public: false } }
    follow_redirect!
    assert_response :success
    @study.reload
    assert_not @study.public

    sign_out @user
    auth_as_user(@sharing_user)
    sign_in @sharing_user
    patch study_path(@study), params: { study: { public: true } }
    follow_redirect!
    assert_equal studies_path, path, 'Did not redirect to My studies page'
    @study.reload
    assert_not @study.public

    sign_out @sharing_user
    get site_path
    patch study_path(@study), params: { study: { public: true } }
    assert_response 302 # redirect to "My studies" page when :check_edit_permissions fires
    follow_redirect!
    assert_response 302 # redirect to sign in page when :authenticate_user! fires
    follow_redirect!
    assert_equal new_user_session_path, path # redirects have finished and path is updated
    @study.reload
    assert_not @study.public
  end
end
