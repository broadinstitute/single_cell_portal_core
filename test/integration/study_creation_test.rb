require "integration_test_helper"

class StudyCreationTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @test_user = User.find_by(email: 'testing.user@gmail.com')
    @sharing_user = User.find_by(email: 'sharing.user@gmail.com')
    auth_as_user(@test_user)
    sign_in @test_user
    @random_seed = File.open(Rails.root.join('.random_seed')).read.strip
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

    bqc = ApplicationController.big_query_client
    bq_dataset = bqc.datasets.detect {|dataset| dataset.dataset_id == CellMetadatum::BIGQUERY_DATASET}
    assert_not_nil bq_dataset, "Did not find #{CellMetadatum::BIGQUERY_DATASET} dataset in BigQuery"
    bq_table = bq_dataset.tables.detect {|table| table.table_id == CellMetadatum::BIGQUERY_TABLE}
    assert_not_nil bq_table, "Did not find #{CellMetadatum::BIGQUERY_TABLE} table in #{CellMetadatum::BIGQUERY_DATASET}"
    initial_bq_row_count = get_bq_row_count(bq_dataset, study)

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
    assert_equal 1, study.expression_matrix_files.size, "Expression matrix failed to associate, found #{study.expression_matrix_files.size} files"
    example_files[:expression][:object] = study.expression_matrix_files.first

    # metadata file
    file_params = {study_file: {file_type: 'Metadata', study_id: study.id.to_s, use_metadata_convention: true}}
    perform_study_file_upload(example_files[:metadata][:path], file_params, study.id)
    assert_response 200, "Metadata upload failed: #{@response.code}"
    example_files[:metadata][:object] = study.metadata_file
    assert example_files[:metadata][:object].present?, "Metadata failed to associate, found no file: #{example_files[:metadata][:object].present?}"

    # first cluster
    file_params = {study_file:
                       {
                           name: 'Test Cluster 1', file_type: 'Cluster', study_id: study.id.to_s,
                           study_file_x_axis_min: -100, study_file_x_axis_max: 100, study_file_y_axis_min: -75,
                           study_file_y_axis_max: 75, study_file_z_axis_min: -125, study_file_z_axis_max: 125,
                           study_file_x_axis_label: 'X Axis', study_file_y_axis_label: 'Y Axis', study_file_z_axis_label: 'Z Axis'
                       }
    }
    perform_study_file_upload(example_files[:cluster][:name], file_params, study.id)
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
    max_seconds_to_sleep = 300
    until ( example_files.values.all? { |e| ['parsed', 'failed'].include? e[:object].parse_status } ) do
      puts "After #{seconds_slept} seconds, " + (example_files.values.map { |e| "#{e[:name]} is #{e[:object].parse_status}"}).join(", ") + '.'
      if seconds_slept >= max_seconds_to_sleep
        raise "Even after #{seconds_slept} seconds, not all files have been parsed."
      end
      sleep(sleep_increment)
      seconds_slept += sleep_increment
      example_files.values.each do |e|
        assert_not e[:object].queued_for_deletion, "parsing #{e[:name]} failed, and is queued for deletion"
        e[:object].reload
      end
    end
    puts "After #{seconds_slept} seconds, " + (example_files.values.map { |e| "#{e[:name]} is #{e[:object].parse_status}"}).join(", ") + '.'

    # confirm that parsing is complete
    example_files.values.each do |e|
      assert_equal 'parsed', e[:object].parse_status, "Incorrect parse_status for #{e[:name]}"
      assert_not e[:object].queued_for_deletion, "#{e[:name]} should be queued for deletion"
    end

    assert_equal 19, study.genes.size, 'Did not parse all genes from expression matrix'

    # verify that counts are correct, this will ensure that everything uploaded & parsed correctly
    cluster_count = study.cluster_groups.size
    metadata_count = study.cell_metadata.size
    cluster_annot_count = study.cluster_annotation_count
    study_file_count = study.study_files.non_primary_data.size
    share_count = study.study_shares.size

    assert_equal 1, cluster_count, "did not find correct number of clusters"
    assert_equal 26, metadata_count, "did not find correct number of metadata objects"
    assert_equal 2, cluster_annot_count, "did not find correct number of cluster annotations"
    assert_equal 3, study_file_count, "did not find correct number of study files"
    assert_equal 1, share_count, "did not find correct number of study shares"

    assert_equal initial_bq_row_count + 30, get_bq_row_count(bq_dataset, study)

    puts "#{File.basename(__FILE__)}: #{self.method_name} successful!"

  end
end
