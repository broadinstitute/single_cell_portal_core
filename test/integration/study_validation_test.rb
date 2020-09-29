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
    file_params = {study_file: {file_type: 'Metadata', study_id: study.id.to_s, use_metadata_convention: true}}
    perform_study_file_upload('metadata_example2.txt', file_params, study.id)
    assert_response 200, "Metadata upload failed: #{@response.code}"
    example_files[:metadata_breaking_convention][:object] = study.metadata_file
    assert example_files[:metadata_breaking_convention][:object].present?, "Metadata failed to associate, found no file: #{example_files[:metadata_breaking_convention][:object].present?}"

    # metadata file that should fail validation because we already have one
    file_params = {study_file: {file_type: 'Metadata', study_id: study.id.to_s}}
    perform_study_file_upload('metadata_bad.txt', file_params, study.id)
    assert_response 422, "Metadata did not fail validation: #{@response.code}"

    # bad cluster
    file_params = {study_file: {name: 'Bad Test Cluster 1', file_type: 'Cluster', study_id: study.id.to_s}}
    perform_study_file_upload('cluster_bad.txt', file_params, study.id)
    assert_response 200, "Cluster 1 upload failed: #{@response.code}"
    assert_equal 1, study.cluster_ordinations_files.size, "Cluster 1 failed to associate, found #{study.cluster_ordinations_files.size} files"
    example_files[:cluster][:object] = study.cluster_ordinations_files.first

    # bad expression matrix (duplicate gene)
    file_params = {study_file: {file_type: 'Expression Matrix', study_id: study.id.to_s}}
    perform_study_file_upload('expression_matrix_example_bad.txt', file_params, study.id)
    assert_response 200, "Expression matrix upload failed: #{@response.code}"
    assert_equal 1, study.expression_matrix_files.size, "Expression matrix failed to associate, found #{study.expression_matrix_files.size} files"
    example_files[:expression][:object] = study.expression_matrix_files.first

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
      assert_equal 'failed', e[:object].parse_status, "Incorrect parse_status for #{e[:name]}"
      assert e[:object].queued_for_deletion
    end

    assert_equal 0, study.cell_metadata.size
    assert_equal 0, study.genes.size
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
            study_detail_attributes: {
                full_description: ""
            },
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

  test 'should delete data from bigquery' do
    puts "#{File.basename(__FILE__)}: #{self.method_name}"

    study = Study.find_by(name: "Test Study #{@random_seed}")
    metadata_file = study.metadata_file
    bqc = ApplicationController.big_query_client
    bq_dataset = bqc.datasets.detect {|dataset| dataset.dataset_id == CellMetadatum::BIGQUERY_DATASET}
    initial_bq_row_count = get_bq_row_count(bq_dataset, study)
    assert initial_bq_row_count == 30, "wrong number of BQ rows found to test deletion capability"
    # request delete
    puts "Requesting delete for alexandria_convention/metadata.v2-0-0.txt"
    delete api_v1_study_study_file_path(study_id: study.id, id: metadata_file.id), as: :json, headers: {authorization: "Bearer #{@test_user.api_access_token[:access_token]}" }

    seconds_slept = 0
    sleep_increment = 10
    max_seconds_to_sleep = 60
    until ( (bq_row_count = get_bq_row_count(bq_dataset, study)) == 0 ) do
      puts "#{seconds_slept} seconds after requesting file deletion, bq_row_count is #{bq_row_count}."
      if seconds_slept >= max_seconds_to_sleep
        raise "Even #{seconds_slept} seconds after requesting file deletion, not all records have been deleted from bigquery."
      end
      sleep(sleep_increment)
      seconds_slept += sleep_increment
    end
    puts "#{seconds_slept} seconds after requesting file deletion, bq_row_count is #{bq_row_count}."
    assert get_bq_row_count(bq_dataset, study) == 0
    puts "#{File.basename(__FILE__)}: #{self.method_name} successful!"
  end

  test 'should allow files with spaces in names' do
    puts "#{File.basename(__FILE__)}: #{self.method_name}"

    study = Study.find_by(name: "Testing Study #{@random_seed}")
    filename = "12_MB_file_with_space_in_filename 2.txt"
    sanitized_filename = filename.gsub(/\s/, '_')
    file_params = {study_file: {file_type: 'Expression Matrix', study_id: study.id.to_s, name: sanitized_filename}}
    exp_matrix = File.open(Rails.root.join('test', 'test_data', filename))
    perform_chunked_study_file_upload(filename, file_params, study.id)
    assert_response 200, "Expression upload failed: #{@response.code}"
    study_file = study.study_files.detect {|file| file.upload_file_name == sanitized_filename}
    refute study_file.nil?, 'Did not find newly uploaded expression matrix'
    assert_equal exp_matrix.size, study_file.upload_file_size, "File sizes do not match; #{exp_matrix.size} != #{study_file.upload_file_size}"

    # clean up
    study_file.destroy

    puts "#{File.basename(__FILE__)}: #{self.method_name} successful!"
  end

  # validates that additional expression matrices with unique cells can be ingested to a study that already has a
  # metadata file and at least one other expression matrix
  test 'should validate unique cells for expression matrices' do
    puts "#{File.basename(__FILE__)}: #{self.method_name}"

    study = Study.find_by(name: "Test Study #{@random_seed}")
    new_matrix = 'expression_matrix_example_2.txt'
    file_params = {study_file: {file_type: 'Expression Matrix', study_id: study.id.to_s}}
    perform_study_file_upload(new_matrix, file_params, study.id)
    assert_response 200, "Expression matrix upload failed: #{@response.code}"
    uploaded_matrix = study.expression_matrix_files.detect {|file| file.upload_file_name == new_matrix}
    assert uploaded_matrix.present?, "Did not find newly uploaded matrix #{new_matrix}"
    puts "Requesting parse for file \"#{uploaded_matrix.upload_file_name}\"."
    assert_equal 'unparsed', uploaded_matrix.parse_status, "Incorrect parse_status for #{new_matrix}"
    initiate_study_file_parse(uploaded_matrix.upload_file_name, study.id)
    assert_response 200, "#{new_matrix} parse job failed to start: #{@response.code}"

    seconds_slept = 60
    puts "Parse initiated for #{new_matrix}, polling for completion"
    sleep seconds_slept
    sleep_increment = 15
    max_seconds_to_sleep = 300
    until  ['parsed', 'failed'].include? uploaded_matrix.parse_status  do
      puts "After #{seconds_slept} seconds, #{new_matrix} is #{uploaded_matrix.parse_status}."
      if seconds_slept >= max_seconds_to_sleep
        raise "Sleep timeout after #{seconds_slept} seconds when waiting for parse of #{new_matrix}."
      end
      sleep(sleep_increment)
      seconds_slept += sleep_increment
      assert_not uploaded_matrix.queued_for_deletion, "parsing #{new_matrix} failed, and is queued for deletion"
      uploaded_matrix.reload
    end
    puts "After #{seconds_slept} seconds, #{new_matrix} is #{uploaded_matrix.parse_status}."

    puts "#{File.basename(__FILE__)}: #{self.method_name} successful!"
  end

  # TODO: once scp-ingest-pipline 1.6.0 is released, re-implement integration test for MTX parsing
  # test 'should parse valid mtx bundle' do
  #   puts "#{File.basename(__FILE__)}: #{self.method_name}"
  #
  #   study = Study.first
  #
  #   # load study files
  #   matrix = study.study_files.by_type('MM Coordinate Matrix').first
  #   genes_file = study.study_files.by_type('10X Genes File').first
  #   barcodes_file = study.study_files.by_type('10X Barcodes File').first
  #   matrix_bundle = matrix.study_file_bundle
  #
  #   # control values
  #   expected_genes = File.open(genes_file.upload.path).readlines.map {|line| line.split.map(&:strip)}
  #   expected_cells = File.open(barcodes_file.upload.path).readlines.map(&:strip)
  #   matrix_file = File.open(matrix.upload.path).readlines
  #   matrix_file.shift(3) # discard header lines
  #   expressed_gene_idx = matrix_file.map {|line| line.split.first.strip.to_i}
  #   expressed_genes = expressed_gene_idx.map {|idx| expected_genes[idx - 1].last}
  #
  #   # upload files and initiate parse
  #   file_params = {study_file: {file_type: 'MM Coordinate Matrix', study_id: study.id.to_s}}
  #   perform_study_file_upload(matrix.name, file_params, study.id)
  #   genes_params = {study_file: {file_type: '10X Genes File', study_id: study.id.to_s, study_file_bundle_id: matrix_bundle.id.to_s}}
  #   perform_study_file_upload(genes_file.name, genes_params, study.id)
  #   study.send_to_firecloud(genes_file)
  #   barcodes_params = {study_file: {file_type: '10X Barcodes File', study_id: study.id.to_s, study_file_bundle_id: matrix_bundle.id.to_s}}
  #   perform_study_file_upload(barcodes_file.name, barcodes_params, study.id)
  #   study.send_to_firecloud(barcodes_file)
  #   initiate_study_file_parse(matrix.upload_file_name, study.id)
  #   seconds_slept = 60
  #   sleep seconds_slept
  #   sleep_increment = 15
  #   max_seconds_to_sleep = 300
  #   until ['parsed', 'failed'].include?(matrix.parse_status) do
  #     puts "After #{seconds_slept} seconds, #{matrix.upload_file_name} is #{matrix.parse_status}"
  #     if seconds_slept >= max_seconds_to_sleep
  #       raise "Even after #{seconds_slept} seconds, not all files have been parsed."
  #     end
  #     sleep(sleep_increment)
  #     seconds_slept += sleep_increment
  #     assert_not matrix.queued_for_deletion, "parsing #{matrix.upload_file_name} failed, and is queued for deletion"
  #     matrix.reload
  #   end
  #   puts "After #{seconds_slept} seconds, #{matrix.upload_file_name} is #{matrix.parse_status}"
  #   study.reload
  #
  #   # validate that the expected significant values have been created
  #   expected_genes.each do |entry|
  #     gene_id, gene_name = entry
  #     gene = study.genes.find_by(name: gene_name)
  #     assert gene_name == gene.name, "Gene names do not match: #{gene_name}, #{gene.name}"
  #     assert gene_id == gene.gene_id, "Gene IDs do not match: #{gene_id}, #{gene.gene_id}"
  #     # if this gene is expected to have expression, then validate the score is correct
  #     if expressed_genes.include?(gene_name)
  #       expected_value = expressed_genes.index(gene_name) + 1
  #       cell_name = gene.scores.keys.first
  #       assert expected_cells.include?(cell_name), "Cell name '#{cell_name}' was not from control list: #{expected_cells}"
  #       value = gene.scores.values.first
  #       assert value == expected_value, "Did not find correct score value for #{gene.name}:#{cell_name}, expected #{expected_value} but found #{value}"
  #     end
  #   end
  #
  #   # clean up
  #   new_config_image.destroy
  #
  #   puts "#{File.basename(__FILE__)}: #{self.method_name} successful!"
  # end
end
