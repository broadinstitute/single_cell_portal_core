require "integration_test_helper"

class StudyValidationTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @test_user = User.find_by(email: 'testing.user@gmail.com')
    @sharing_user = User.find_by(email: 'sharing.user@gmail.com')
    auth_as_user(@test_user)
    sign_in @test_user
    @random_seed = File.open(Rails.root.join('.random_seed')).read.strip
  end

  # check that file header/format checks still function properly
  test 'should fail all ingest pipeline parse jobs' do
    puts "#{File.basename(__FILE__)}: #{self.method_name}"
    study_params = {
        study: {
            name: "Ingest Pipeline Parse Failure Study #{@random_seed}",
            user_id: @test_user.id
        }
    }
    post studies_path, params: study_params
    follow_redirect!
    assert_response 200, "Did not redirect to upload successfully"
    study = Study.find_by(name: "Ingest Pipeline Parse Failure Study #{@random_seed}")
    assert study.present?, "Study did not successfully save"

    example_files = {
      metadata: {
        name: 'metadata_bad.txt'
      },
      metadata_breaking_convention: {
        name: 'metadata_example2.txt'
      },
      cluster: {
        name: 'cluster_bad.txt'
      }
    }

    ## upload files

    # bad metadata file
    file_params = {study_file: {file_type: 'Metadata', study_id: study.id.to_s}}
    perform_study_file_upload('metadata_bad.txt', file_params, study.id)
    assert_response 200, "Metadata upload failed: #{@response.code}"
    example_files[:metadata][:object] = study.metadata_file
    assert example_files[:metadata][:object].present?, "Metadata failed to associate, found no file: #{example_files[:metadata][:object].present?}"

    # good metadata file, but falsely claiming to use the metadata_convention
    file_params = {study_file: {file_type: 'Metadata', study_id: study.id.to_s, use_metadata_convention: true}}
    perform_study_file_upload('metadata_example2.txt', file_params, study.id)
    assert_response 200, "Metadata upload failed: #{@response.code}"
    example_files[:metadata_breaking_convention][:object] = study.metadata_file
    assert example_files[:metadata_breaking_convention][:object].present?, "Metadata failed to associate, found no file: #{example_files[:metadata_breaking_convention][:object].present?}"

    # bad cluster
    file_params = {study_file: {name: 'Bad Test Cluster 1', file_type: 'Cluster', study_id: study.id.to_s}}
    perform_study_file_upload('cluster_bad.txt', file_params, study.id)
    assert_response 200, "Cluster 1 upload failed: #{@response.code}"
    assert_equal 1, study.cluster_ordinations_files.size, "Cluster 1 failed to associate, found #{study.cluster_ordinations_files.size} files"
    example_files[:cluster][:object] = study.cluster_ordinations_files.first

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
    max_seconds_to_sleep = 180
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
      assert_equal 'failed', e[:object].parse_status, "Incorrect parse_status for #{e[:name]}"
      assert e[:object].queued_for_deletion
    end

    assert_equal 0, study.cell_metadata.size
    assert_equal 0, study.cluster_groups.size
    assert_equal 0, study.cluster_ordinations_files.size

    puts "#{File.basename(__FILE__)}: #{self.method_name} successful!"
  end

  test 'should fail all local parse jobs' do
    puts "#{File.basename(__FILE__)}: #{self.method_name}"
    study_params = {
        study: {
            name: "Local Parse Failure Study #{@random_seed}",
            user_id: @test_user.id
        }
    }
    post studies_path, params: study_params
    follow_redirect!
    assert_response 200, "Did not redirect to upload successfully"
    study = Study.find_by(name: "Local Parse Failure Study #{@random_seed}")
    assert study.present?, "Study did not successfully save"

    # bad expression matrix
    file_params = {study_file: {file_type: 'Expression Matrix', study_id: study.id.to_s}}
    perform_study_file_upload('expression_matrix_example_bad.txt', file_params, study.id)
    assert_response 200, "Expression matrix upload failed: #{@response.code}"
    assert study.expression_matrix_files.size == 1, "Expression matrix failed to associate, found #{study.expression_matrix_files.size} files"
    expression_matrix_1 = study.expression_matrix_files.first
    # this parse has a duplicate gene, which will throw an error
    begin
      study.initialize_gene_expression_data(expression_matrix_1, @test_user)
    rescue => e
      assert e.is_a?(StandardError), "Caught unknown error during parse: #{e.class}:#{e.message}"
    end

    assert study.genes.size == 0, "Found #{study.genes.size} genes when should have found 0"
    assert study.expression_matrix_files.size == 0,
           "Found #{study.expression_matrix_files.size} expression matrices when should have found 0"

    # bad marker gene list
    file_params = {study_file: {name: 'Bad Test Gene List', file_type: 'Gene List', study_id: study.id.to_s}}
    perform_study_file_upload('marker_1_gene_list_bad.txt', file_params, study.id)
    assert_response 200, "Gene list upload failed: #{@response.code}"
    assert study.study_files.where(file_type: 'Gene List').size == 1,
           "Gene list failed to associate, found #{study.study_files.where(file_type: 'Gene List').size} files"
    gene_list_file = study.study_files.where(file_type: 'Gene List').first
    # this parse has a duplicate gene, which will not throw an error - it is caught internally
    study.initialize_precomputed_scores(gene_list_file, @test_user)
    # we have to reload the study because it will have a cached reference to the precomputed_score due to the nature of the parse
    study = Study.find_by(name: "Local Parse Failure Study #{@random_seed}")
    assert study.study_files.where(file_type: 'Gene List').size == 0,
           "Found #{study.study_files.where(file_type: 'Gene List').size} gene list files when should have found 0"
    assert study.precomputed_scores.size == 0, "Found #{study.precomputed_scores.size} precomputed scores when should have found 0"

    puts "#{File.basename(__FILE__)}: #{self.method_name} successful!"
  end

  test 'should prevent changing firecloud attributes' do
    puts "#{File.basename(__FILE__)}: #{self.method_name}"
    study_params = {
        study: {
            name: "FireCloud Attribute Test #{@random_seed}",
            user_id: @test_user.id
        }
    }
    post studies_path, params: study_params
    follow_redirect!
    assert_response 200, "Did not redirect to upload successfully"
    study = Study.find_by(name: "FireCloud Attribute Test #{@random_seed}")
    assert study.present?, "Study did not successfully save"

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
    study = Study.find_by(name: "FireCloud Attribute Test #{@random_seed}")
    assert_equal FireCloudClient::PORTAL_NAMESPACE, study.firecloud_project,
                 "FireCloud project was not correct, expected #{FireCloudClient::PORTAL_NAMESPACE} but found #{study.firecloud_project}"
    assert_equal "firecloud-attribute-test-#{@random_seed}", study.firecloud_workspace,
                 "FireCloud workspace was not correct, expected test-firecloud-attribute-test-#{@random_seed} but found #{study.firecloud_workspace}"
    puts "#{File.basename(__FILE__)}: #{self.method_name} successful!"
  end

  test 'should disable downloads for reviewers' do
    puts "#{File.basename(__FILE__)}: #{self.method_name}"
    study_params = {
        study: {
            name: "Reviewer Share #{@random_seed}",
            user_id: @test_user.id,
            public: false,
            study_shares_attributes: {
                "0" => {
                    email: @sharing_user.email,
                    permission: 'Reviewer'
                }
            }
        }
    }
    post studies_path, params: study_params
    follow_redirect!
    assert_response 200, "Did not complete request successfully, expected redirect and response 200 but found #{@response.code}"
    study = Study.find_by(name: "Reviewer Share #{@random_seed}")
    assert study.study_shares.size == 1, "Did not successfully create study_share, found #{study.study_shares.size} shares"
    reviewer_email = study.study_shares.reviewers.first
    assert reviewer_email == @sharing_user.email, "Did not grant reviewer permission to #{@sharing_user.email}, reviewers: #{reviewer_email}"


    # load private study and validate reviewer can see study but not download data
    sign_out @test_user
    auth_as_user(@sharing_user)
    sign_in @sharing_user
    get view_study_path(accession: study.accession, study_name: study.url_safe_name)
    assert controller.current_user == @sharing_user,
           "Did not successfully authenticate as sharing user, current_user is #{controller.current_user.email}"
    assert_select "h1.study-lead", true, "Did not successfully load study page for #{study.name}"
    assert_select 'li#study-download-nav' do |element|
      assert element.attr('class').to_str.include?('disabled'), "Did not disable downloads tab for reviewer: '#{element.attr('class')}'"
    end


    # ensure direct call to download is still disabled
    get download_private_file_path(accession: study.accession, study_name: study.url_safe_name, filename: 'README.txt')
    follow_redirect!
    assert_equal view_study_path(accession: study.accession, study_name: study.url_safe_name), path,
                 "Did not block download and redirect to study page, current path is #{path}"
    puts "#{File.basename(__FILE__)}: #{self.method_name} successful!"
  end

  test 'should redirect for detached studies' do
    puts "#{File.basename(__FILE__)}: #{self.method_name}"
    study = Study.find_by(name: "Testing Study #{@random_seed}")
    # manually set 'detached' to true to validate file download requests fail
    study.update(detached: true)

    # try to download a file
    file = study.study_files.first
    get download_file_path(accession: study.accession, study_name: study.url_safe_name, filename: file.upload_file_name)
    assert_response 302, "Did not attempt to redirect on a download from a detached study, expected 302 but found #{response.code}"

    # reset 'detached' so downstream tests don't fail
    study.update(detached: false)
    puts "#{File.basename(__FILE__)}: #{self.method_name} successful!"
  end
end

