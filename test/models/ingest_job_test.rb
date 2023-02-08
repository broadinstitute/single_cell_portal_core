require 'test_helper'

class IngestJobTest < ActiveSupport::TestCase

  before(:all) do
    @user = FactoryBot.create(:user, test_array: @@users_to_clean)
    @basic_study = FactoryBot.create(:detached_study,
                                     name_prefix: 'IngestJob Test',
                                     user: @user,
                                     test_array: @@studies_to_clean)

    @basic_study_exp_file = FactoryBot.create(:study_file,
                                              name: 'dense.txt',
                                              file_type: 'Expression Matrix',
                                              study: @basic_study)

    @pten_gene = FactoryBot.create(:gene_with_expression,
                                   name: 'PTEN',
                                   study_file: @basic_study_exp_file,
                                   expression_input: [['A', 0],['B', 3],['C', 1.5]])
    @basic_study_exp_file.build_expression_file_info(is_raw_counts: false,
                                                     library_preparation_protocol: 'MARS-seq',
                                                     modality: 'Transcriptomic: unbiased',
                                                     biosample_input_type: 'Whole cell')
    @basic_study_exp_file.parse_status = 'parsed'
    @basic_study_exp_file.upload_file_size = 1024
    @basic_study_exp_file.save!

    # insert "all cells" array for this expression file
    DataArray.create!(study_id: @basic_study.id, study_file_id: @basic_study_exp_file.id, values: %w(A B C),
                      name: "#{@basic_study_exp_file.name} Cells", array_type: 'cells', linear_data_type: 'Study',
                      linear_data_id: @basic_study.id, array_index: 0, cluster_name: @basic_study_exp_file.name)

    @other_matrix = FactoryBot.create(:study_file,
                                       name: 'dense_2.txt',
                                       file_type: 'Expression Matrix',
                                       study: @basic_study)
    @other_matrix.build_expression_file_info(is_raw_counts: false, library_preparation_protocol: 'MARS-seq',
                                             modality: 'Transcriptomic: unbiased', biosample_input_type: 'Whole cell')
    @other_matrix.upload_file_size = 2048
    @other_matrix.save!
  end

  test 'should hold ingest until other matrix validates' do

    ingest_job = IngestJob.new(study: @basic_study, study_file: @other_matrix, action: :ingest_expression)
    assert ingest_job.can_launch_ingest?, 'Should be able to launch ingest job but can_launch_ingest? returned false'

    # simulate parse job is underway, but file has already validated
    @basic_study_exp_file.update_attributes!(parse_status: 'parsing')
    concurrent_job = IngestJob.new(study: @basic_study, study_file: @other_matrix, action: :ingest_expression)
    assert concurrent_job.can_launch_ingest?,
           'Should be able to launch ingest job of concurrent parse but can_launch_ingest? returned false'

    # simulate parse job has not started by removing parsed data
    DataArray.where(study_id: @basic_study.id, study_file_id: @basic_study_exp_file.id).delete_all
    Gene.where(study_id: @basic_study.id, study_file_id: @basic_study_exp_file.id).delete_all
    queued_job = IngestJob.new(study: @basic_study, study_file: @other_matrix, action: :ingest_expression)
    refute queued_job.can_launch_ingest?,
           'Should not be able to launch ingest job of queued parse but can_launch_ingest? returned true'

    # show that after 24 hours the job can launch (simulating a failed ingest launch that blocks other parses)
    @basic_study_exp_file.update_attributes!(created_at: 25.hours.ago)
    assert queued_job.can_launch_ingest?,
           'Should be able to launch ingest job of queued parse after 24 hours but can_launch_ingest? returned false'

    # simulate new matrix is "older" by backdating created_at by 1 week
    @other_matrix.update_attributes!(created_at: 1.week.ago.in_time_zone)
    backdated_job = IngestJob.new(study: @basic_study, study_file: @other_matrix, action: :ingest_expression)
    assert backdated_job.can_launch_ingest?,
           'Should be able to launch ingest job of backdated parse but can_launch_ingest? returned false'

    # ensure other matrix types are not gated
    raw_counts_matrix = FactoryBot.create(:study_file,
                                          name: 'raw.txt',
                                          file_type: 'Expression Matrix',
                                          study: @basic_study)
    raw_counts_matrix.build_expression_file_info(is_raw_counts: true, units: 'raw counts',
                                                 library_preparation_protocol: 'MARS-seq',
                                                 modality: 'Transcriptomic: unbiased',
                                                 biosample_input_type: 'Whole cell')

    raw_counts_matrix.save!
    raw_counts_ingest = IngestJob.new(study: @basic_study, study_file: raw_counts_matrix, action: :ingest_expression)
    assert raw_counts_ingest.can_launch_ingest?,
           'Should be able to launch raw counts ingest job but can_launch_ingest? returned false'

  end

  test 'should gather job properties to report to mixpanel' do
    # positive test
    job = IngestJob.new(study: @basic_study, study_file: @basic_study_exp_file, user: @user, action: :ingest_expression)
    mock = Minitest::Mock.new
    now = DateTime.now.in_time_zone
    mock_metadata = {
      events: [
        { timestamp: now.to_s },
        { timestamp: (now + 1.minute).to_s }
      ],
      pipeline: {
        resources: {
          virtualMachine: {
            machineType: 'n1-highmem-4',
            bootDiskSizeGb: 300
          }
        }
      }
    }.with_indifferent_access
    mock.expect :metadata, mock_metadata
    mock.expect :metadata, mock_metadata
    mock.expect :error, nil

    cells = @basic_study.expression_matrix_cells(@basic_study_exp_file)
    num_cells = cells.present? ? cells.count : 0

    ApplicationController.papi_client.stub :get_pipeline, mock do
      expected_outputs = {
        perfTime: 60000,
        fileType: @basic_study_exp_file.file_type,
        fileSize: @basic_study_exp_file.upload_file_size,
        fileName: @basic_study_exp_file.name,
        trigger: 'upload',
        action: :ingest_expression,
        studyAccession: @basic_study.accession,
        jobStatus: 'success',
        numGenes: @basic_study.genes.count,
        is_raw_counts: false,
        numCells: num_cells,
        machineType: 'n1-highmem-4',
        bootDiskSizeGb: 300
      }.with_indifferent_access

      job_analytics = job.get_job_analytics
      mock.verify
      assert_equal expected_outputs, job_analytics
    end

    # negative test
    job = IngestJob.new(study: @basic_study, study_file: @other_matrix, user: @user, action: :ingest_expression)
    mock = Minitest::Mock.new
    now = DateTime.now.in_time_zone
    mock_metadata = {
      events: [
        { timestamp: now.to_s },
        { timestamp: (now + 2.minutes).to_s }
      ],
      pipeline: {
        resources: {
          virtualMachine: {
            machineType: 'n1-highmem-4',
            bootDiskSizeGb: 300
          }
        }
      }
    }.with_indifferent_access
    mock.expect :metadata, mock_metadata
    mock.expect :metadata, mock_metadata
    mock.expect :error, { code: 1, message: 'mock message' } # simulate error

    ApplicationController.papi_client.stub :get_pipeline, mock do
      expected_outputs = {
        perfTime: 120000,
        fileType: @other_matrix.file_type,
        fileSize: @other_matrix.upload_file_size,
        fileName: @other_matrix.name,
        trigger: "upload",
        action: :ingest_expression,
        studyAccession: @basic_study.accession,
        jobStatus: 'failed',
        numCells: 0,
        is_raw_counts: false,
        numGenes: 0,
        machineType: 'n1-highmem-4',
        bootDiskSizeGb: 300
      }.with_indifferent_access

      job_analytics = job.get_job_analytics
      mock.verify
      assert_equal expected_outputs, job_analytics
    end
  end

  test 'should limit size when reading error logfile for email' do
    job = IngestJob.new(study: @basic_study, study_file: @basic_study_exp_file, user: @user, action: :ingest_expression)
    file_location = @basic_study_exp_file.bucket_location
    output_length = 1024

    # test both with & without range and assert limit is enforced
    [nil, (0...100)].each do |range|
      output = StringIO.new(SecureRandom.alphanumeric(output_length))
      mock = Minitest::Mock.new
      mock.expect :workspace_file_exists?, true, [@basic_study.bucket_id, file_location]
      mock.expect :execute_gcloud_method, output, [:read_workspace_file, 0, @basic_study.bucket_id, file_location]
      ApplicationController.stub :firecloud_client, mock do
        contents = job.read_parse_logfile(file_location, delete_on_read: false, range: range)
        mock.verify
        expected_size = range.present? ? range.last: output_length
        assert_equal expected_size, contents.size
        # ensure correct bytes are returned
        output.rewind
        expected_output = range.present? ? output.read[range] : output.read
        assert_equal expected_output, contents
      end
    end
  end

  test 'should set default annotation even if not visualizable' do
    assert @basic_study.default_annotation.nil?
    # test metadata file with a single annotation with only one unique value
    metadata_file = FactoryBot.create(:metadata_file,
                                      name: 'metadata.txt',
                                      study: @basic_study,
                                      cell_input: %w[A B C],
                                      annotation_input: [
                                        { name: 'species', type: 'group', values: %w[dog dog dog] }
                                      ])
    job = IngestJob.new(study: @basic_study, study_file: metadata_file, user: @user, action: :ingest_cell_metadata)
    job.set_study_default_options
    @basic_study.reload
    assert_equal 'species--group--invalid', @basic_study.default_annotation

    # reset default annotation, then test cluster file with a single annotation with only one unique value
    @basic_study.cell_metadata.destroy_all
    @basic_study.default_options = {}
    @basic_study.save
    assert @basic_study.default_annotation.nil?
    assert @basic_study.default_cluster.nil?
    cluster_file = FactoryBot.create(:cluster_file,
                                     name: 'cluster.txt', study: @basic_study,
                                     cell_input: {
                                       x: [1, 4, 6],
                                       y: [7, 5, 3],
                                       cells: %w[A B C]
                                     },
                                     annotation_input: [{ name: 'foo', type: 'group', values: %w[bar bar bar] }])
    job = IngestJob.new(study: @basic_study, study_file: cluster_file, user: @user, action: :ingest_cluster)
    job.set_study_default_options
    @basic_study.reload
    cluster = @basic_study.cluster_groups.first
    assert_equal cluster, @basic_study.default_cluster
    assert_equal 'foo--group--invalid', @basic_study.default_annotation
  end

  test 'should launch DE jobs if study is eligible' do
    study = FactoryBot.create(:detached_study,
                              name_prefix: 'DE Job Test',
                              user: @user,
                              test_array: @@studies_to_clean)
    raw = FactoryBot.create(
      :expression_file, name: 'raw.txt', study: study, upload_file_size: 300,
      expression_file_info: {
        is_raw_counts: true, units: 'raw counts', library_preparation_protocol: 'Drop-seq',
        biosample_input_type: 'Whole cell', modality: 'Proteomic'
      }
    )
    DataArray.create!(study_id: study.id, study_file_id: raw.id, values: %w[A B C],
                      name: "#{raw.name} Cells", array_type: 'cells', linear_data_type: 'Study',
                      linear_data_id: study.id, array_index: 0, cluster_name: raw.name)
    FactoryBot.create(
      :cluster_file, name: 'clusterA.txt', study: study,
      cell_input: { x: [1, 4, 6], y: [7, 5, 3], cells: %w[A B C] },
      annotation_input: [
        { name: 'foo', type: 'group', values:%w[bar bar baz] }
      ]
    )
    FactoryBot.create(
      :metadata_file, name: 'metadata.txt', study: study, cell_input: %w[A B C],
      annotation_input: [
        { name: 'species', type: 'group', values: %w[dog cat dog] },
        { name: 'disease', type: 'group', values: %w[none none measles] },
        {
          name: 'cell_type__ontology_label',
          type: 'group',
          values: ['B cell', 'T cell', 'B cell', ]
        },
        {
          name: 'cell_type',
          type: 'group',
          values: %w[CL_0000236 CL_0000084 CL_0000236]
        },
        {
          name: 'cell_type__custom',
          type: 'group',
          values: %w[ImmN Hb-VC ImmN]
        }
      ])
    job = IngestJob.new(study:)
    job_mock = Minitest::Mock.new
    2.times do
      job_mock.expect(:push_remote_and_launch_ingest, Delayed::Job.new)
    end
    mock = Minitest::Mock.new
    2.times do
      mock.expect(:delay, job_mock)
    end
    IngestJob.stub :new, mock do
      job.launch_differential_expression_jobs
      mock.verify
      job_mock.verify
    end
  end
end
