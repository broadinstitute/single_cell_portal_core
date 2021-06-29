require "test_helper"

class FileParseServiceTest < ActiveSupport::TestCase

  include Minitest::Hooks
  include SelfCleaningSuite
  include TestInstrumentor

  before(:all) do
    @user = FactoryBot.create(:api_user, test_array: @@users_to_clean)
    @basic_study = FactoryBot.create(:detached_study,
                                     name_prefix: 'File Parse Service Test',
                                     user: @user,
                                     test_array: @@studies_to_clean)
  end

  # test detection & automatic creating of study_file_bundle objects based off of study_file.options params
  test 'should create study file bundle from parent' do
    # test MTX bundling from parent
    test_data_basepath = Rails.root.join('test', 'test_data', 'GRCh38')
    matrix_filename = 'test_matrix.mtx'
    genes_filename = 'test_genes.tsv'
    barcodes_filename = 'barcodes.tsv'
    matrix_file = File.open(File.join(test_data_basepath, matrix_filename))
    genes_file = File.open(File.join(test_data_basepath, genes_filename))
    barcodes_file = File.open(File.join(test_data_basepath, barcodes_filename))
    # status: 'uploaded' is required for study_file_bundle to be marked as 'completed'
    matrix = @basic_study.study_files.build(file_type: 'MM Coordinate Matrix', upload: matrix_file, name: matrix_filename,
                                     status: 'uploaded')
    matrix.save!
    genes = @basic_study.study_files.build(file_type: '10X Genes File', upload: genes_file, name: genes_filename,
                                    options: {matrix_id: matrix.id.to_s}, status: 'uploaded')
    barcodes = @basic_study.study_files.build(file_type: '10X Barcodes File', upload: barcodes_file, name: barcodes_filename,
                                       options: {matrix_id: matrix.id.to_s}, status: 'uploaded')
    genes.save!
    barcodes.save!
    FileParseService.create_bundle_from_file_options(matrix, @basic_study)
    matrix_file.close
    genes_file.close
    barcodes_file.close
    matrix.reload
    parent_bundle = matrix.study_file_bundle
    assert parent_bundle.present?, "Did not create study file bundle for matrix file"
    assert parent_bundle.parent == matrix, "Did not correctly mark matrix file as bundle parent"
    assert parent_bundle.completed?, "Did not correctly mark bundle as completed with all 3 files present"
    bundled_filenames = parent_bundle.bundled_files.pluck(:upload_file_name)
    [genes, barcodes].each do |bundle_file|
      bundle_file.reload
      filename = bundle_file.upload_file_name
      assert bundled_filenames.include?(filename), "Cannot find #{filename} in #{bundled_filenames}"
      assert bundle_file.study_file_bundle == parent_bundle,
             "Did not associate correct study file bundle object for #{filename}"
    end
  end

  test 'should create study file bundle from child' do
    # test cluster/labels bundling from child/bundled file
    test_data_basepath = Rails.root.join('test', 'test_data')
    cluster_filename = 'cluster_2_example_2.txt'
    cluster_file = File.open(File.join(test_data_basepath, cluster_filename))
    cluster = @basic_study.study_files.build(file_type: 'Cluster', upload: cluster_file, name: cluster_filename,
                                      status: 'uploaded')
    cluster.save!
    coordinate_filename = 'coordinate_labels_1.txt'
    coordinate_file = File.open(File.join(test_data_basepath, coordinate_filename))
    coordinate_labels = @basic_study.study_files.build(file_type: 'Coordinate Labels', upload: coordinate_file,
                                                name: coordinate_filename, status: 'uploaded',
                                                options: {cluster_file_id: cluster.id.to_s})
    coordinate_labels.save!
    FileParseService.create_bundle_from_file_options(coordinate_labels, @basic_study)
    cluster.reload
    coordinate_labels.reload
    cluster_bundle = cluster.study_file_bundle
    assert cluster_bundle.present?, "Did not create study file bundle for cluster file w/ coordinate labels present"
    assert cluster_bundle.completed?, "Did not mark cluster bundle completed"
    assert cluster_bundle.bundled_files.first == coordinate_labels, "Did not correctly return labels file from bundle"
  end

  test 'should clean up ingest artifacts after one month' do
    file_mock = Minitest::Mock.new
    two_months_ago = DateTime.now - 2.months
    file_mock.expect :size, 1024
    file_mock.expect :created_at, two_months_ago
    file_mock.expect :name, 'file.txt'
    file_mock.expect :delete, true
    bucket_mock = Minitest::Mock.new
    bucket_mock.expect :execute_gcloud_method, [file_mock], [:get_workspace_files, Integer, String, Hash]

    ApplicationController.stub :firecloud_client, bucket_mock do
      FileParseService.delete_ingest_artifacts(@basic_study, 30.days.ago)
      bucket_mock.verify
      file_mock.verify
    end
  end

  test 'should prevent parsing coordinate label file after cluster deletes' do
    @cluster_file = FactoryBot.create(:cluster_file, name: 'clusterA.txt', study: @basic_study,
                                      cell_input: { x: [1, 4 ,6], y: [7, 5, 3], cells: ['A', 'B', 'C'] },
                                      annotation_input: [{ name: 'foo', type: 'group', values: ['bar', 'bar', 'baz'] }])

    # don't use factory bot as we want to test parsing logic
    File.open(Rails.root.join('test', 'test_data', 'coordinate_labels_2.txt')) do |upload|
      @coordinate_file = StudyFile.create!(file_type: 'Coordinate Labels', name: 'coordinate_labels_2.txt',
                                           study_id: @basic_study.id, upload: upload,
                                           options: { cluster_file_id: @cluster_file.id.to_s })
    end

    # simulate "failed" upload by queuing cluster file for deletion
    @cluster_file.update(queued_for_deletion: true)
    DeleteQueueJob.new(@cluster_file).perform

    # attempt to parse coordinate file and assert 412 response and that no study_file_bundle is created
    response = FileParseService.run_parse_job(@coordinate_file, @basic_study, @user)
    @coordinate_file.reload
    assert_equal 412, response[:status_code]
    assert_nil @coordinate_file.study_file_bundle
  end
end
