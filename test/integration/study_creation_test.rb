require 'integration_test_helper'
require 'big_query_helper'
require 'ingest_job_helper'

class StudyCreationTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @test_user = User.find_by(email: 'testing.user@gmail.com')
    @sharing_user = User.find_by(email: 'sharing.user@gmail.com')
    auth_as_user(@test_user)
    sign_in @test_user
    @random_seed = File.open(Rails.root.join('.random_seed')).read.strip
  end

  teardown do
    OmniAuth.config.mock_auth[:google] = nil
  end

  test 'create default testing study' do

    puts "#{File.basename(__FILE__)}: #{self.method_name}"
    study_params = {
        study: {
            name: "Test Study #{@random_seed}",
            user_id: @test_user.id,
            study_shares_attributes: {
                "0" => {
                    email: @sharing_user.email,
                    permission: 'Edit'
              }
            }
        }
    }
    post studies_path, params: study_params
    follow_redirect!
    assert_response 200, "Did not redirect to upload successfully"
    sleep 1
    study = Study.find_by(name: "Test Study #{@random_seed}")
    assert study.present?, "Study did not successfully save"
    initial_bq_row_count = get_bq_row_count(study)

    example_files = {
      expression: {
        name: 'expression_matrix_example.txt'
      },
      metadata: {
        name: 'metadata.v2-0-0.txt',
        path: 'alexandria_convention/metadata.v2-0-0.txt'
      },
      cluster: {
        name: 'cluster_example_2.txt'
      }
    }

    ## upload files

    # expression matrix #1
    file_params = {study_file: {file_type: 'Expression Matrix', study_id: study.id.to_s}}
    perform_study_file_upload(example_files[:expression][:name], file_params, study.id)
    assert_response 200, "Expression matrix upload failed: #{@response.code}"

    # metadata file
    file_params = {study_file: {file_type: 'Metadata', study_id: study.id.to_s, use_metadata_convention: true}}
    perform_study_file_upload(example_files[:metadata][:path], file_params, study.id)
    assert_response 200, "Metadata upload failed: #{@response.code}"

    # first cluster
    file_params = {study_file: { name: 'Test Cluster 1', file_type: 'Cluster', study_id: study.id.to_s } }
    perform_study_file_upload(example_files[:cluster][:name], file_params, study.id)
    assert_response 200, "Cluster 1 upload failed: #{@response.code}"
    assert_equal 1, study.cluster_ordinations_files.size, "Cluster 1 failed to associate, found #{study.cluster_ordinations_files.size} files"

    ## request parse
    example_files.each do |file_type,file|
      puts "Requesting parse for file \"#{file[:name]}\"."
      initiate_study_file_parse(file[:name], study.id)
      assert_response 200, "#{file_type} parse job failed to start: #{@response.code}"
    end

    sleep 30
    example_files.each do |file_type, file|
      puts "retrieving PAPI run for file \"#{file[:name]}\"."
      study_file = study.study_files.detect { |f| f.upload_file_name == file[:name] }
      pipeline = get_ingest_pipeline_run(study_file)
      example_files[file_type][:ingest_run] = pipeline
    end

    seconds_slept = 30
    sleep seconds_slept
    sleep_increment = 15
    max_seconds_to_sleep = 300
    until example_files.values.all? { |file| file[:ingest_run].done? } do
      puts "After #{seconds_slept} seconds, " + (example_files.values.map { |e| "#{e[:name]} is still parsing"}).join(", ") + '.'
      raise "Even after #{seconds_slept} seconds, not all files have been parsed." if seconds_slept >= max_seconds_to_sleep
      sleep(sleep_increment)
      seconds_slept += sleep_increment
    end

    # confirm that parsing is complete
    example_files.values.each do |file|
      refute file[:ingest_run].error.present? # successful ingest runs will not have any errors
    end

    assert_equal 19, study.genes.size, 'Did not parse all genes from expression matrix'

    # verify that counts are correct, this will ensure that everything uploaded & parsed correctly
    cluster_count = study.cluster_groups.size
    metadata_count = study.cell_metadata.size
    gene_count = study.genes.size
    cluster_annot_count = study.cluster_annotation_count
    study_file_count = study.study_files.non_primary_data.size
    share_count = study.study_shares.size

    assert_equal 1, cluster_count, "did not find correct number of clusters"
    assert_equal 26, metadata_count, "did not find correct number of metadata objects"
    assert_equal 19, gene_count, "did not find correct number of gene objects"
    assert_equal 2, cluster_annot_count, "did not find correct number of cluster annotations"
    assert_equal 3, study_file_count, "did not find correct number of study files"
    assert_equal 1, share_count, "did not find correct number of study shares"

    assert_equal initial_bq_row_count + 30, get_bq_row_count(study)

    # check that the cluster_group set the point count
    cluster_group = study.cluster_groups.first
    assert_equal 30, cluster_group.points

    puts "#{File.basename(__FILE__)}: #{self.method_name} successful!"
  end

  # new studies in PORTAL_NAMESPACE should have workspace owners set to SA owner group, not SA directly
  test 'should assign service account owner group as workspace owner' do
    puts "#{File.basename(__FILE__)}: #{self.method_name}"

    study_name = "Workspace Owner #{@random_seed}"
    study_params = {
        study: {
            name: study_name,
            user_id: @test_user.id
        }
    }
    post studies_path, params: study_params
    follow_redirect!
    study = Study.find_by(name: study_name)
    assert study.present?, "Study did not successfully save"
    sa_owner_group = AdminConfiguration.find_or_create_ws_user_group!
    group_email = sa_owner_group['groupEmail']
    workspace_acl = ApplicationController.firecloud_client.get_workspace_acl(study.firecloud_project, study.firecloud_workspace)
    group_acl = workspace_acl['acl'][group_email]
    assert group_acl['accessLevel']  == 'OWNER', "Did not correctly set #{group_email} to 'OWNER'; #{group_acl}"

    # clean up
    ApplicationController.firecloud_client.delete_workspace(study.firecloud_project, study.firecloud_workspace)
    study.destroy

    puts "#{File.basename(__FILE__)}: #{self.method_name} successful!"
  end
end
