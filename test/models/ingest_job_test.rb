require 'test_helper'

class IngestJobTest < ActiveSupport::TestCase

  before(:all) do
    @user = FactoryBot.create(:user, test_array: @@users_to_clean)
    @basic_study = FactoryBot.create(:detached_study,
                                     name_prefix: 'IngestJob Test',
                                     user: @user,
                                     test_array: @@studies_to_clean)

    @basic_study_exp_file = FactoryBot.create(:expression_file,
                                              name: 'dense.txt',
                                              file_type: 'Expression Matrix',
                                              study: @basic_study,
                                              expression_input: {
                                                'PTEN' => [['A', 0],['B', 3],['C', 1.5]]
                                              })

    @basic_study_exp_file.build_expression_file_info(is_raw_counts: false,
                                                     library_preparation_protocol: 'MARS-seq',
                                                     modality: 'Transcriptomic: unbiased',
                                                     biosample_input_type: 'Whole cell')
    @basic_study_exp_file.parse_status = 'parsed'
    @basic_study_exp_file.upload_file_size = 1024
    @basic_study_exp_file.save!

    @other_matrix = FactoryBot.create(:study_file,
                                       name: 'dense_2.txt',
                                       file_type: 'Expression Matrix',
                                       study: @basic_study)
    @other_matrix.build_expression_file_info(is_raw_counts: false, library_preparation_protocol: 'MARS-seq',
                                             modality: 'Transcriptomic: unbiased', biosample_input_type: 'Whole cell')
    @other_matrix.upload_file_size = 2048
    @other_matrix.save!
    @basic_study.reload
    @now = DateTime.now.in_time_zone
  end

  teardown do
    @basic_study.default_options[:annotation] = nil
    @basic_study.save
    @basic_study_exp_file.update(parse_status: 'parsed')
  end

  after(:all) do
    Delayed::Job.delete_all # remove any unneeded jobs that will pollute logs with errors later
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
    study = FactoryBot.create(:detached_study,
                              name_prefix: 'IngestJob Mixpanel Test',
                              user: @user,
                              test_array: @@studies_to_clean)

    study_file = FactoryBot.create(:expression_file,
                                   name: 'matrix.txt',
                                   study:,
                                   expression_input: {
                                     'Phex' => [['A', 1],['B', 2],['C', 0.5]]
                                   })

    study_file.build_expression_file_info(is_raw_counts: false,
                                         library_preparation_protocol: "10x 5' v3",
                                         modality: 'Transcriptomic: unbiased',
                                         biosample_input_type: 'Whole cell')
    study_file.upload_file_size = 1.megabyte
    study_file.save!
    pipeline_name = SecureRandom.uuid
    job = IngestJob.new(pipeline_name:, study:, study_file:, user: @user, action: :ingest_expression)
    mock = Minitest::Mock.new
    vm_info = {
      cpu_milli: 4000,
      memory_mib: 32768,
      machine_type: 'n2d-highmem-4',
      boot_disk_size_gb: 300
    }.with_indifferent_access

    dummy_job = Google::Apis::BatchV1::Job.new(
      status: Google::Apis::BatchV1::JobStatus.new(
        state: 'SUCCEEDED',
        status_events: [
          Google::Apis::BatchV1::StatusEvent.new(event_time: @now.to_s),
          Google::Apis::BatchV1::StatusEvent.new(event_time: (@now + 1.minute).to_s)
        ]
      )
    )

    4.times { mock.expect :get_job, dummy_job, [pipeline_name] }
    mock.expect :get_job_resources, vm_info, [], job: dummy_job
    mock.expect :exit_code_from_task, 0, [pipeline_name]

    cells = study.expression_matrix_cells(study_file)
    num_cells = cells.count

    ApplicationController.stub :batch_api_client, mock do
      expected_outputs = {
        perfTime: 60000,
        fileType: study_file.file_type,
        fileSize: study_file.upload_file_size,
        fileName: study_file.name,
        trigger: 'upload',
        action: :ingest_expression,
        studyAccession: study.accession,
        jobStatus: 'success',
        numGenes: study.genes.count,
        is_raw_counts: false,
        numCells: num_cells,
        machineType: 'n2d-highmem-4',
        bootDiskSizeGb: 300,
        exitStatus: 0
      }.with_indifferent_access

      job_analytics = job.get_job_analytics
      mock.verify
      assert_equal expected_outputs, job_analytics
    end

    # negative test
    other_file = FactoryBot.create(:study_file,
                                   name: 'matrix_2.txt',
                                   file_type: 'Expression Matrix',
                                   study:)
    other_file.build_expression_file_info(is_raw_counts: false, library_preparation_protocol: 'MARS-seq',
                                          modality: 'Transcriptomic: unbiased', biosample_input_type: 'Whole cell')
    other_file.upload_file_size = 2048
    other_file.save!
    failed_pipeline = SecureRandom.uuid
    job = IngestJob.new(
      pipeline_name: failed_pipeline, study:, study_file: other_file, user: @user, action: :ingest_expression
    )
    mock = Minitest::Mock.new

    vm_info = {
      cpu_milli: 4000,
      memory_mib: 32768,
      machine_type: 'n2d-highmem-4',
      boot_disk_size_gb: 300
    }.with_indifferent_access

    failed_job = Google::Apis::BatchV1::Job.new(
      status: Google::Apis::BatchV1::JobStatus.new(
        state: 'FAILED',
        status_events: [
          Google::Apis::BatchV1::StatusEvent.new(event_time: @now.to_s),
          Google::Apis::BatchV1::StatusEvent.new(event_time: (@now + 2.minute).to_s)
        ]
      )
    )

    4.times { mock.expect :get_job, failed_job, [failed_pipeline] }
    mock.expect :get_job_resources, vm_info, [], job: failed_job
    mock.expect :exit_code_from_task, 1, [failed_pipeline]

    ApplicationController.stub :batch_api_client, mock do
      expected_outputs = {
        perfTime: 120000,
        fileType: other_file.file_type,
        fileSize: other_file.upload_file_size,
        fileName: other_file.name,
        trigger: "upload",
        action: :ingest_expression,
        studyAccession: study.accession,
        jobStatus: 'failed',
        numCells: 0,
        is_raw_counts: false,
        numGenes: 0,
        machineType: 'n2d-highmem-4',
        bootDiskSizeGb: 300,
        exitStatus: 1
      }.with_indifferent_access

      job_analytics = job.get_job_analytics
      mock.verify
      assert_equal expected_outputs, job_analytics
    end
  end

  test 'should identify AnnData parses with extraction in mixpanel' do
    # parsed AnnData
    ann_data_file = FactoryBot.create(:ann_data_file,
                                      name: 'test.h5ad',
                                      study: @basic_study,
                                      upload_file_size: 1.megabyte,
                                      cell_input: %w[A B C D],
                                      has_raw_counts: true,
                                      reference_file: false,
                                      annotation_input: [
                                        { name: 'disease', type: 'group', values: %w[cancer cancer normal normal] }
                                      ],
                                      coordinate_input: [
                                        { umap: { x: [1, 2, 3, 4], y: [5, 6, 7, 8] } }
                                      ],
                                      expression_input: {
                                        'phex' => [['A', 0.3], ['B', 1.0], ['C', 0.5], ['D', 0.1]]
                                      })
    params_object = AnnDataIngestParameters.new(
      anndata_file: ann_data_file.gs_url, obsm_keys: ann_data_file.ann_data_file_info.obsm_key_names,
      file_size: ann_data_file.upload_file_size, extract_raw_counts: true
    )
    assert params_object.extract.include?('raw_counts')
    job_name = SecureRandom.uuid
    job = IngestJob.new(
      pipeline_name: job_name, study: @basic_study, study_file: ann_data_file, user: @user,
      action: :ingest_anndata, params_object:
    )
    mock = Minitest::Mock.new
    vm_info = {
      cpu_milli: 4000,
      memory_mib: 32768,
      machine_type: 'n2d-highmem-4',
      boot_disk_size_gb: 300
    }.with_indifferent_access
    mock_job = Google::Apis::BatchV1::Job.new(
      status: Google::Apis::BatchV1::JobStatus.new(
        state: 'SUCCEEDED',
        status_events: [
          Google::Apis::BatchV1::StatusEvent.new(event_time: @now.to_s),
          Google::Apis::BatchV1::StatusEvent.new(event_time: (@now + 1.minute).to_s)
        ]
      )
    )
    4.times { mock.expect :get_job, mock_job, [job_name] }
    mock.expect :get_job_resources, vm_info, [], job: mock_job
    mock.expect :exit_code_from_task, 0, [job_name]

    ApplicationController.stub :batch_api_client, mock do
      expected_outputs = {
        perfTime: 60000,
        fileType: ann_data_file.file_type,
        fileSize: ann_data_file.upload_file_size,
        fileName: ann_data_file.name,
        trigger: 'upload',
        action: :ingest_anndata,
        studyAccession: @basic_study.accession,
        jobStatus: 'success',
        referenceAnnDataFile: false,
        extractedFileTypes: %w[cluster metadata processed_expression raw_counts],
        machineType: 'n2d-highmem-4',
        bootDiskSizeGb: 300,
        exitStatus: 0
      }.with_indifferent_access

      job_analytics = job.get_job_analytics
      mock.verify
      assert_equal expected_outputs, job_analytics
    end

    # reference AnnData
    reference_file = FactoryBot.create(:ann_data_file, name: 'reference.h5ad', study: @basic_study)
    reference_file.upload_file_size = 1.megabyte
    reference_file.save
    params_object = AnnDataIngestParameters.new(
      anndata_file: reference_file.gs_url, extract: nil, obsm_keys: nil, file_size: reference_file.upload_file_size
    )
    reference_pipeline = SecureRandom.uuid
    job = IngestJob.new(
      pipeline_name: reference_pipeline, study: @basic_study, study_file: reference_file, user: @user,
      action: :ingest_anndata, params_object:
    )
    mock = Minitest::Mock.new
    vm_info = {
      cpu_milli: 4000,
      memory_mib: 32768,
      machine_type: 'n2d-highmem-4',
      boot_disk_size_gb: 300
    }.with_indifferent_access
    mock_job = Google::Apis::BatchV1::Job.new(
      status: Google::Apis::BatchV1::JobStatus.new(
        state: 'SUCCEEDED',
        status_events: [
          Google::Apis::BatchV1::StatusEvent.new(event_time: @now.to_s),
          Google::Apis::BatchV1::StatusEvent.new(event_time: (@now + 1.minute).to_s)
        ]
      )
    )
    4.times { mock.expect :get_job, mock_job, [reference_pipeline] }
    mock.expect :get_job_resources, vm_info, [], job: mock_job
    mock.expect :exit_code_from_task, 0, [reference_pipeline]

    ApplicationController.stub :batch_api_client, mock do
      expected_outputs = {
        perfTime: 60000,
        fileType: reference_file.file_type,
        fileSize: reference_file.upload_file_size,
        fileName: reference_file.name,
        trigger: 'upload',
        action: :ingest_anndata,
        studyAccession: @basic_study.accession,
        jobStatus: 'success',
        referenceAnnDataFile: true,
        extractedFileTypes: nil,
        machineType: 'n2d-highmem-4',
        bootDiskSizeGb: 300,
        exitStatus: 0
      }.with_indifferent_access

      job_analytics = job.get_job_analytics
      mock.verify
      assert_equal expected_outputs, job_analytics
    end
  end

  test 'should get ingestSummary for AnnData parsing' do
    ann_data_file = FactoryBot.create(:ann_data_file, name: 'data.h5ad', study: @basic_study)
    ann_data_file.ann_data_file_info.reference_file = false
    ann_data_file.ann_data_file_info.data_fragments = [
      { _id: BSON::ObjectId.new.to_s, data_type: :cluster, obsm_key_name: 'X_umap', name: 'UMAP' }
    ]
    ann_data_file.upload_file_size = 1.megabyte
    ann_data_file.options[:anndata_summary] = false
    ann_data_file.save
    cluster_file = RequestUtils.data_fragment_url(ann_data_file, 'cluster', file_type_detail: 'X_umap')
    params_object = AnnDataIngestParameters.new(
      ingest_cluster: true, name: 'UMAP', cluster_file:, domain_ranges: {}, ingest_anndata: false,
      extract: nil, obsm_keys: nil
    )
    pipeline_name = SecureRandom.uuid
    job = IngestJob.new(
      pipeline_name:, study: @basic_study, study_file: ann_data_file, user: @user, action: :ingest_cluster, params_object:
    )
    dummy_job = Google::Apis::BatchV1::Job.new(
      name: pipeline_name,
      create_time: @now.to_s,
      update_time: (@now + 1.minute).to_s,
      status: Google::Apis::BatchV1::JobStatus.new(
        state: 'SUCCEEDED',
        status_events: [
          Google::Apis::BatchV1::StatusEvent.new(event_time: @now.to_s),
          Google::Apis::BatchV1::StatusEvent.new(event_time: (@now + 1.minute).to_s)
        ]
      )
    )

    mock_commands = [
      'python', 'ingest_pipeline.py', '--study-id', @basic_study.id.to_s, '--study-file-id',
      ann_data_file.id.to_s, 'ingest_cluster', '--ingest-cluster', '--cluster-file', cluster_file,
      '--name', 'UMAP', '--domain-ranges', '{}'
    ]

    list_mock = Minitest::Mock.new
    list_mock.expect :jobs, [dummy_job]

    mock = Minitest::Mock.new
    mock.expect :list_jobs, list_mock
    mock.expect :job_done?, true, [dummy_job]
    3.times { mock.expect :get_job_command_line, mock_commands, [], job: dummy_job }
    2.times { mock.expect :job_error, false, [pipeline_name] }

    ApplicationController.stub :batch_api_client, mock do
      expected_job_props = {
        perfTime: 60000,
        fileName: ann_data_file.name,
        fileType: 'AnnData',
        fileSize: ann_data_file.upload_file_size,
        studyAccession: @basic_study.accession,
        trigger: ann_data_file.upload_trigger,
        jobStatus: 'success',
        numFilesExtracted: 1,
        machineType: params_object.machine_type,
        action: nil,
        exitCode: 0
      }
      job_props = job.anndata_summary_props
      assert_equal expected_job_props, job_props
      mock.verify
    end
  end

  test 'should report AnnData summary to Mixpanel' do
    ann_data_file = FactoryBot.create(:ann_data_file, name: 'matrix.h5ad', study: @basic_study)
    ann_data_file.ann_data_file_info.reference_file = false
    ann_data_file.ann_data_file_info.data_fragments = [
      { _id: BSON::ObjectId.new.to_s, data_type: :cluster, obsm_key_name: 'X_umap', name: 'UMAP' }
    ]
    ann_data_file.upload_file_size = 1.megabyte
    ann_data_file.options[:anndata_summary] = false
    ann_data_file.save

    cell_metadata_file = RequestUtils.data_fragment_url(ann_data_file, 'metadata')
    metadata_params = AnnDataIngestParameters.new(
      ingest_cell_metadata: true, cell_metadata_file:, ingest_anndata: false, extract: nil, obsm_keys: nil,
      study_accession: @basic_study.accession
    )
    metadata_job = IngestJob.new(study: @basic_study, study_file: ann_data_file, user: @user,
                                 action: :ingest_metadata, params_object: metadata_params)
    cluster_file = RequestUtils.data_fragment_url(ann_data_file, 'cluster', file_type_detail: 'X_umap')
    cluster_params_object = AnnDataIngestParameters.new(
      ingest_cluster: true, name: 'UMAP', cluster_file:, domain_ranges: {}, ingest_anndata: false,
      extract: nil, obsm_keys: nil
    )
    pipeline_name = SecureRandom.uuid
    cluster_job = IngestJob.new(
      pipeline_name:, study: @basic_study, study_file: ann_data_file, user: @user, action: :ingest_cluster,
      params_object: cluster_params_object
    )
    job_mock = Minitest::Mock.new
    2.times { job_mock.expect :object, cluster_job }
    dummy_job = Google::Apis::BatchV1::Job.new(status: Google::Apis::BatchV1::JobStatus.new(state: 'RUNNING'))

    pipeline_mock = Minitest::Mock.new
    pipeline_mock.expect :get_job, dummy_job, [pipeline_name]

    # negative test
    DelayedJobAccessor.stub :find_jobs_by_handler_type, [Delayed::Job.new] do
      DelayedJobAccessor.stub :dump_job_handler, job_mock do
        ApplicationController.stub :batch_api_client, pipeline_mock do
          metadata_job.report_anndata_summary
          job_mock.verify
          pipeline_mock.verify
          ann_data_file.reload
          assert_not ann_data_file.has_anndata_summary?
        end
      end
    end

    mock_job_props = {
      perfTime: 60000,
      fileName: ann_data_file.name,
      fileType: 'AnnData',
      fileSize: ann_data_file.upload_file_size,
      studyAccession: @basic_study.accession,
      trigger: ann_data_file.upload_trigger,
      jobStatus: 'success',
      numFilesExtracted: 1,
      machineType: metadata_params.machine_type,
      action: nil,
      exitCode: 0
    }
    metrics_mock = Minitest::Mock.new
    metrics_mock.expect :call, true, ['ingestSummary', mock_job_props, @user]

    # positive test
    DelayedJobAccessor.stub :find_jobs_by_handler_type, [] do
      MetricsService.stub :log, metrics_mock do
        cluster_job.stub :anndata_summary_props, mock_job_props do
          cluster_job.report_anndata_summary
          ann_data_file.reload
          assert ann_data_file.has_anndata_summary?
          metrics_mock.verify
        end
      end
    end
  end

  test 'should report failure step in ingestSummary' do
    ann_data_file = FactoryBot.create(:ann_data_file, name: 'failed.h5ad', study: @basic_study)
    pipeline_name = SecureRandom.uuid
    dummy_job = Google::Apis::BatchV1::Job.new(
      name: pipeline_name,
      create_time: (@now - 1.hour).to_s,
      update_time: @now.to_s,
      status: Google::Apis::BatchV1::JobStatus.new(
        state: 'FAILED',
        status_events: [
          Google::Apis::BatchV1::StatusEvent.new(event_time: (@now - 1.hour).to_s),
          Google::Apis::BatchV1::StatusEvent.new(event_time: @now.to_s)
        ]
      )
    )

    mock_commands = ['python', 'ingest_pipeline.py', '--study-file-id', ann_data_file.id.to_s, 'ingest_cell_metadata']

    list_mock = Minitest::Mock.new
    list_mock.expect :jobs, [dummy_job]
    job_error = Google::Apis::BatchV1::StatusEvent.new(
      event_time: @now.to_s,
      task_state: 'FAILED',
      task_execution: Google::Apis::BatchV1::TaskExecution.new(exit_code: 65)
    )
    mock = Minitest::Mock.new
    mock.expect :list_jobs, list_mock
    mock.expect :job_done?, true, [dummy_job]
    mock.expect :exit_code_from_task, 65, [pipeline_name]
    4.times { mock.expect :get_job_command_line, mock_commands, [], job: dummy_job }
    3.times { mock.expect :job_error, job_error, [pipeline_name] }
    ApplicationController.stub :batch_api_client, mock do
      cell_metadata_file = RequestUtils.data_fragment_url(ann_data_file, 'metadata')
      metadata_params = AnnDataIngestParameters.new(
        ingest_cell_metadata: true, cell_metadata_file:, ingest_anndata: false, extract: nil, obsm_keys: nil,
        study_accession: @basic_study.accession
      )
      metadata_job = IngestJob.new(pipeline_name:, study: @basic_study, study_file: ann_data_file, user: @user,
                                   action: :ingest_metadata, params_object: metadata_params)
      props = metadata_job.anndata_summary_props.with_indifferent_access
      assert_equal 3_600_000, props[:perfTime]
      assert_equal 'failed', props[:jobStatus]
      assert_equal 0, props[:numFilesExtracted]
      assert_equal 'ingest_cell_metadata', props[:action]
      assert_equal 65, props[:exitCode]
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
    study = FactoryBot.create(:detached_study,
                              name_prefix: 'Default Annotation Test',
                              user: @user,
                              test_array: @@studies_to_clean)
    assert study.default_annotation.nil?
    # test metadata file with a single annotation with only one unique value
    metadata_file = FactoryBot.create(:metadata_file,
                                      name: 'metadata.txt',
                                      study:,
                                      cell_input: %w[A B C],
                                      annotation_input: [
                                        { name: 'species', type: 'group', values: %w[dog dog dog] }
                                      ])
    job = IngestJob.new(study:, study_file: metadata_file, user: @user, action: :ingest_cell_metadata)
    job.set_study_default_options
    study.reload
    assert_equal 'species--group--invalid', study.default_annotation

    # reset default annotation, then test cluster file with a single annotation with only one unique value
    study.cell_metadata.destroy_all
    study.default_options = {}
    study.save
    assert study.default_annotation.nil?
    assert study.default_cluster.nil?
    cluster_file = FactoryBot.create(:cluster_file,
                                     name: 'cluster.txt', study:,
                                     cell_input: {
                                       x: [1, 4, 6],
                                       y: [7, 5, 3],
                                       cells: %w[A B C]
                                     },
                                     annotation_input: [{ name: 'foo', type: 'group', values: %w[bar bar bar] }])
    job = IngestJob.new(study:, study_file: cluster_file, user: @user, action: :ingest_cluster)
    job.set_study_default_options
    study.reload
    cluster = study.cluster_groups.first
    assert_equal cluster, study.default_cluster
    assert_equal 'foo--group--invalid', study.default_annotation
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

  test 'should create differential expression results from user-uploaded file' do
    study = FactoryBot.create(:detached_study,
                              name_prefix: 'User DE Test',
                              user: @user,
                              test_array: @@studies_to_clean)
    coords = 1.upto(20).to_a
    cells = coords.map { |i| "cell_#{i}" }
    cluster_name = 'de_cluster.txt'
    cell_types = [
      'B cells', 'CSN1S1 macrophages', 'dendritic cells', 'eosinophils', 'fibroblasts', 'GPMNB macrophages', 'LC1',
      'LC2', 'neutrophils', 'T cells'
    ]
    values = cell_types + cell_types
    FactoryBot.create(:metadata_file,
                      name: 'metadata.txt',
                      study:,
                      cell_input: cells,
                      annotation_input: [{ name: 'cell_type__custom', type: 'group', values: }]
    )
    cluster_file = FactoryBot.create(:cluster_file,
                                     name: cluster_name,
                                     study:,
                                     cell_input: { x: coords, y: coords, cells: }
    )
    cluster_group = ClusterGroup.find_by(study:, study_file: cluster_file)
    de_file = FactoryBot.create(:differential_expression_file,
                                study:,
                                name: 'user_de.txt',
                                annotation_name: 'cell_type__custom',
                                annotation_scope: 'study',
                                cluster_group:,
                                computational_method: 'custom'
    )
    job = IngestJob.new(study:, study_file: de_file, action: :ingest_differential_expression, user: @user)
    mock = Minitest::Mock.new
    manifest = File.open(
      Rails.root.join('test', 'test_data', 'differential_expression', 'All_Cells_UMAP--General_Celltype--manifest.tsv')
    )
    mock.expect(:execute_gcloud_method, manifest, [:read_workspace_file, 0, study.bucket_id, String])
    ApplicationController.stub :firecloud_client, mock do
      job.create_author_differential_expression_results
      mock.verify

      de_result = DifferentialExpressionResult.find_by(study:, study_file: de_file, annotation_name: 'cell_type__custom')
      assert de_result.present?
      assert de_result.is_author_de
      expected_one_vs_rest = cell_types.dup - ['CSN1S1 macrophages']
      assert_equal expected_one_vs_rest, de_result.one_vs_rest_comparisons
      expected_pairwise_keys = cell_types.dup - ['T cells']
      assert_equal expected_pairwise_keys, de_result.pairwise_comparisons.keys
      assert_not_includes de_result.pairwise_comparisons['B cells'], 'CSN1S1 macrophages'
    end
  end

  test 'should handle ingest failure by action' do
    study = FactoryBot.create(:detached_study,
                              name_prefix: 'IngestJob Fail Test',
                              user: @user,
                              test_array: @@studies_to_clean)
    # test subsampling fail logic
    cluster_file = FactoryBot.create(
      :cluster_file, name: 'UMAP.txt', study:,
      cell_input: { x: [1, 2, 3], y: [1, 2, 3], cells: %w[cellA cellB cellC] }
    )
    cluster = study.cluster_groups.by_name('UMAP.txt')
    cluster.update(is_subsampling: true)
    pipeline_name = SecureRandom.uuid

    job = IngestJob.new(pipeline_name:, study:, study_file: cluster_file, user: @user, action: :ingest_subsample)

    error_log = "parse_logs/#{cluster_file.id}/user_log.txt"
    mock = Minitest::Mock.new
    mock.expect :workspace_file_exists?, true, [study.bucket_id, error_log]
    mock.expect(
      :execute_gcloud_method,
      StringIO.new("error"),
      [:read_workspace_file, 0, study.bucket_id, error_log]
    )
    mock.expect :execute_gcloud_method, true,
                [:delete_workspace_file, 0, study.bucket_id, error_log]

    batch_mock = Minitest::Mock.new
    batch_mock.expect :get_job, Google::Apis::BatchV1::Job, [pipeline_name]
    batch_mock.expect :get_job_command_line, %w[foo bar bing baz], [], job: Google::Apis::BatchV1::Job
    ApplicationController.stub :firecloud_client, mock do
      ApplicationController.stub :batch_api_client, batch_mock do
        job.handle_ingest_failure('parse failure')
        cluster_file.reload
        study.reload
        cluster.reload
        assert cluster_file.parsed?
        assert cluster.present?
        assert_not cluster.is_subsampling?
        assert_equal 3, cluster.concatenate_data_arrays('text', 'cells').count
        mock.verify
      end
    end

    # normal fail
    failed_file = FactoryBot.create(
      :cluster_file, name: 'tSNE.txt', study:,
      cell_input: { x: [1, 2, 3], y: [1, 2, 3], cells: %w[cellA cellB cellC] }
    )
    pipeline_name = SecureRandom.uuid
    failed_job = IngestJob.new(
      pipeline_name:, study:, study_file: failed_file, user: @user, action: :ingest_cluster
    )
    error_log = "parse_logs/#{failed_file.id}/user_log.txt"
    mock = Minitest::Mock.new
    mock.expect :execute_gcloud_method, true,
                [:copy_workspace_file, 0, study.bucket_id, failed_file.bucket_location, failed_file.parse_fail_bucket_location]
    mock.expect :delete_workspace_file, true, [study.bucket_id, failed_file.bucket_location]
    mock.expect :workspace_file_exists?, true, [study.bucket_id, error_log]
    mock.expect(
      :execute_gcloud_method,
      StringIO.new("error"),
      [:read_workspace_file, 0, study.bucket_id, error_log]
    )
    mock.expect :execute_gcloud_method, true,
                [:delete_workspace_file, 0, study.bucket_id, error_log]

    batch_mock = Minitest::Mock.new
    batch_mock.expect :get_job, Google::Apis::BatchV1::Job, [pipeline_name]
    batch_mock.expect :get_job_command_line, %w[foo bar bing baz], [], job: Google::Apis::BatchV1::Job
    ApplicationController.stub :firecloud_client, mock do
      ApplicationController.stub :batch_api_client, batch_mock do
        failed_job.handle_ingest_failure('parse failure')
        mock.verify
      end
    end
  end

  test 'should perform secondary cleanup if AnnData subparse fails' do
    study = FactoryBot.create(:detached_study,
                                name_prefix: 'Secondary Cleanup Test',
                                user: @user,
                                test_array: @@studies_to_clean)
    study_file = FactoryBot.create(:ann_data_file,
                                   name: 'data.h5ad',
                                   study:,
                                   cell_input: %w[A B C D],
                                   annotation_input: [
                                     { name: 'disease', type: 'group', values: %w[cancer cancer normal normal] }
                                   ],
                                   coordinate_input: [
                                     { tsne: { x: [1, 2, 3, 4], y: [5, 6, 7, 8] } }
                                   ],
                                   expression_input: {
                                     'phex' => [['A', 0.3], ['B', 1.0], ['C', 0.5], ['D', 0.1]]
                                   })
    study.reload
    assert_equal 1, study.cluster_groups.count
    assert_equal 1, study.cell_metadata.count
    assert_equal 1, study.genes.count

    study_file.set_anndata_summary!
    study_file.reload
    safe_fragment = study_file.ann_data_file_info.fragments_by_type(:cluster).first.with_indifferent_access
    cluster = study.cluster_groups.first
    cluster_file = RequestUtils.data_fragment_url(
      study_file, 'cluster', file_type_detail: safe_fragment[:obsm_key_name]
    )
    cell_metadata_file = RequestUtils.data_fragment_url(study_file, 'metadata')
    params_object = AnnDataIngestParameters.new(
      subsample: true, ingest_anndata: false, extract: nil, obsm_keys: nil, name: cluster.name,
      cluster_file:, cell_metadata_file:
    )

    job = IngestJob.new(
      pipeline_name: SecureRandom.uuid, study:, study_file:, user: @user, action: :ingest_subsample, params_object:
    )
    batch_job = Google::Apis::BatchV1::Job.new(
      status: Google::Apis::BatchV1::JobStatus.new(
        state: 'SUCCEEDED',
        status_events: [
          Google::Apis::BatchV1::StatusEvent.new(event_time: @now.to_s),
          Google::Apis::BatchV1::StatusEvent.new(event_time: (@now + 1.minute).to_s)
        ]
      )
    )
    mock = Minitest::Mock.new
    3.times { mock.expect :get_job, batch_job, [job.pipeline_name] }
    ApplicationController.stub :batch_api_client, mock do
      study_file.update(queued_for_deletion: true)
      job.poll_for_completion
      study.reload
      assert study.cluster_groups.empty?
      assert study.cell_metadata.empty?
      assert study.genes.empty?
      mock.verify
    end
  end

  test 'should ensure email delivery and parse_status reset on special action failures' do
    study = FactoryBot.create(:detached_study,
                              name_prefix: 'Special Action Email',
                              user: @user,
                              test_array: @@studies_to_clean)
    study_file = FactoryBot.create(:ann_data_file,
                                   name: 'matrix.h5ad',
                                   study:,
                                   upload_file_size: 1.megabyte,
                                   cell_input: %w[A B C D],
                                   expression_input: {
                                     'phex' => [['A', 0.3], ['B', 1.0], ['C', 0.5], ['D', 0.1]]
                                   },
                                   annotation_input: [
                                     { name: 'disease', type: 'group', values: %w[cancer cancer normal normal] }
                                   ],
                                   coordinate_input: [
                                     { umap: { x: [1, 2, 3, 4], y: [5, 6, 7, 8] } }
                                   ])
    bucket = study.bucket_id
    annotation_file = "gs://#{bucket}/anndata/h5ad_frag.metadata.tsv"
    cluster_file = "gs://#{bucket}/anndata/h5ad_frag.cluster.X_umap.tsv"
    params_object = DifferentialExpressionParameters.new(
      matrix_file_path: "gs://#{bucket}/matrix.h5ad", matrix_file_type: 'h5ad', file_size: study_file.upload_file_size,
      annotation_file:, cluster_file:, cluster_name: 'umap', annotation_name: 'disease', annotation_scope: 'study',
      cluster_group_id: BSON::ObjectId.new
    )
    pipeline_name = SecureRandom.uuid
    study_file.update(parse_status: 'parsing')
    job = IngestJob.new(
      pipeline_name:, study:, study_file:, user: @user, action: :differential_expression, params_object:
    )
    dummy_job = Google::Apis::BatchV1::Job.new(
      status: Google::Apis::BatchV1::JobStatus.new(
        state: 'FAILED',
        status_events: [
          Google::Apis::BatchV1::StatusEvent.new(event_time: @now.to_s),
          Google::Apis::BatchV1::StatusEvent.new(event_time: (@now + 2.minute).to_s)
        ]
      )
    )
    mock_commands = [
      'python', 'ingest_pipeline.py', '--study-id', study.id.to_s, '--study-file-id',
      study_file.id.to_s, 'differential_expression', '--differential-expression', '--cluster-file', cluster_file,
      '--annotation-file', annotation_file, '--cluster-name', 'umap', '--annotation-name', 'disease',
      '--annotation-scope', 'study'
    ]
    vm_info = {
      cpu_milli: 4000,
      memory_mib: 32768,
      machine_type: 'n2d-highmem-4',
      boot_disk_size_gb: 300
    }.with_indifferent_access

    mock = Minitest::Mock.new
    mock.expect :get_job_resources, vm_info, [], job: dummy_job
    mock.expect :get_job_command_line, mock_commands, [], job: dummy_job
    12.times { mock.expect :get_job, dummy_job, [pipeline_name] }
    2.times { mock.expect :exit_code_from_task, 1, [pipeline_name] }

    email_mock = Minitest::Mock.new
    email_mock.expect :deliver_now, true
    ApplicationController.stub :batch_api_client, mock do
      SingleCellMailer.stub :notify_admin_parse_fail, email_mock do
        job.poll_for_completion
        # ensure that parse_status flag is reset after failure
        study_file.reload
        assert study_file.parsed?
        mock.verify
        email_mock.verify
      end
    end
  end

  test 'should automatically retry on OOM failure' do
    study = FactoryBot.create(:detached_study,
                              name_prefix: 'OOM Test',
                              user: @user,
                              test_array: @@studies_to_clean)
    study_file = FactoryBot.create(:ann_data_file,
                                   name: 'matrix.h5ad',
                                   study:,
                                   upload_file_size: 8.gigabytes,
                                   cell_input: %w[A B C D],
                                   coordinate_input: [
                                     { umap: { x: [1, 2, 3, 4], y: [5, 6, 7, 8] } }
                                   ])
    params_object = AnnDataIngestParameters.new(
      anndata_file: "gs://#{study.bucket_id}/matrix.h5ad", file_size: study_file.upload_file_size
    )
    pipeline_name = SecureRandom.uuid
    job = IngestJob.new(
      pipeline_name:, study:, study_file:, user: @user, action: :ingest_anndata, params_object:
    )
    bucket = study.bucket_id

    commands = [
      'python', 'ingest_pipeline.py', '--study-id', study.id.to_s, '--study-file-id',
      study_file.id.to_s, 'ingest_anndata', '--ingest-anndata', '--anndata-file', params_object.anndata_file,
      '--obsm-keys', '["X_umap"]', '--extract', '["cluster", "metadata", "processed_expression", "raw_counts"]'
    ]

    dummy_job = Google::Apis::BatchV1::Job.new(
      name: pipeline_name,
      create_time: (@now - 3.minutes).to_s,
      update_time: @now.to_s,
      status: Google::Apis::BatchV1::JobStatus.new(
        state: 'FAILED',
        status_events: [
          Google::Apis::BatchV1::StatusEvent.new(event_time: (@now - 3.minutes).to_s),
          Google::Apis::BatchV1::StatusEvent.new(event_time: @now.to_s)
        ]
      )
    )

    vm_info = {
      cpu_milli: 8000,
      memory_mib: 131072,
      machine_type: 'n2d-highmem-8',
      boot_disk_size_gb: 300
    }.with_indifferent_access

    # must mock batch_api_client getting pipeline metadata
    client_mock = Minitest::Mock.new
    4.times { client_mock.expect :exit_code_from_task, 137, [pipeline_name] }
    client_mock.expect :get_job_resources, vm_info, [], job: dummy_job
    client_mock.expect :get_job_command_line, commands, [], job: dummy_job
    # new pipeline mock is resubmitted job with larger machine_type
    new_pipeline = Minitest::Mock.new
    new_op = Google::Apis::BatchV1::Job.new(
      name: 'oom-retry',
      status: Google::Apis::BatchV1::JobStatus.new(state:'RUNNING')
    )
    2.times do
      client_mock.expect :get_job, new_op, [new_op.name]
      new_pipeline.expect :done?, false, []
      new_pipeline.expect :failed?, false
    end
    # block for keyword arguments allows better control of assertions
    # also prevents mock 'unexpected arguments' errors that can happen
    client_mock.expect :run_job, new_op do |args|
      args[:study_file].upload_file_name == study_file.upload_file_name &&
        args[:study_file].id.to_s == study_file.id.to_s && # this should be the exact same file
        args[:action] == :ingest_anndata &&
        args[:params_object].machine_type == 'n2d-highmem-16'
    end
    terra_mock = Minitest::Mock.new
    terra_mock.expect :get_workspace_file,
                      Google::Cloud::Storage::File.new,
                      [bucket, study_file.bucket_location]
    terra_mock.expect :workspace_file_exists?,
                      false,
                      [bucket, String]
    job.stub :get_ingest_run, dummy_job do
      ApplicationController.stub :batch_api_client, client_mock do
        ApplicationController.stub :firecloud_client, terra_mock do
          job.poll_for_completion
          terra_mock.verify
          client_mock.verify
        end
      end
    end
  end

  test 'should always unset subsampling flags' do
    study = FactoryBot.create(:detached_study,
                              name_prefix: 'Subsample Flag Test',
                              user: @user,
                              test_array: @@studies_to_clean)
    # test subsampling flags where no new data was ingested
    study_file = FactoryBot.create(
      :cluster_file, name: 'UMAP.txt', study:,
      cell_input: { x: [1, 2, 3], y: [1, 2, 3], cells: %w[cellA cellB cellC] }
    )
    cluster = study.cluster_groups.by_name('UMAP.txt')
    cluster.update(is_subsampling: true)
    job = IngestJob.new(pipeline_name: SecureRandom.uuid, study:, study_file:, user: @user, action: :ingest_subsample)
    job.set_subsampling_flags
    cluster.reload
    assert_not cluster.is_subsampling
  end

  test 'should create differential expression result on completion' do
    study = FactoryBot.create(:detached_study,
                               name_prefix: 'DifferentialExpressionResult Test',
                               user: @user,
                               test_array: @@studies_to_clean)

    cells = %w[A B C D E]
    matrix = FactoryBot.create(:expression_file,
                                name: 'raw.txt',
                                study:,
                                expression_file_info: {
                                  is_raw_counts: true,
                                  units: 'raw counts',
                                  library_preparation_protocol: 'Drop-seq',
                                  biosample_input_type: 'Whole cell',
                                  modality: 'Proteomic'
                                })
    cluster_file = FactoryBot.create(:cluster_file,
                                     name: 'cluster_diffexp.txt',
                                     study:,
                                     cell_input: {
                                       x: [1, 4, 6, 8, 9],
                                       y: [7, 5, 3, 2, 1],
                                       cells:
                                     }
    )
    cluster_group = study.cluster_groups.by_name('cluster_diffexp.txt')
    FactoryBot.create(:metadata_file,
                      name: 'metadata.txt',
                      study:,
                      cell_input: cells,
                      annotation_input: [
                        {
                          name: 'cell_type__ontology_label',
                          type: 'group',
                          values: ['B cell', 'B cell', 'T cell', 'B cell', 'T cell']
                        }
                      ]
    )

    # one vs rest test
    one_vs_rest = DifferentialExpressionParameters.new(
      annotation_name: 'cell_type__ontology_label', annotation_scope: 'study', cluster_name: 'cluster_diffexp.txt',
      matrix_file_path: "gs://#{study.bucket_id}/raw.txt", cluster_group_id: cluster_group.id
    )
    job = IngestJob.new(study:, study_file: cluster_file, action: :differential_expression, params_object: one_vs_rest)
    job.create_differential_expression_results

    result = DifferentialExpressionResult.find_by(
      study:, annotation_name: 'cell_type__ontology_label', annotation_scope: 'study', matrix_file_id: matrix.id,
      cluster_group:
    )
    assert result.present?
    assert_equal ['B cell', 'T cell'], result.one_vs_rest_comparisons

    # pairwise test
    pairwise = DifferentialExpressionParameters.new(
      annotation_name: 'cell_type__ontology_label', annotation_scope: 'study', cluster_name: 'cluster_diffexp.txt',
      matrix_file_path: "gs://#{study.bucket_id}/raw.txt", de_type: 'pairwise', group1: 'B cell', group2: 'T cell',
      cluster_group_id: cluster_group.id
    )
    job = IngestJob.new(study:, study_file: cluster_file, action: :differential_expression, params_object: pairwise)
    job.create_differential_expression_results

    # should be the same DE result with existing one vs. rest results
    result.reload
    assert_equal ['T cell'], result.pairwise_comparisons['B cell']
    assert_equal ['B cell', 'T cell'], result.one_vs_rest_comparisons
  end
end
