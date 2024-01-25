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
        { timestamp: now.to_s }.with_indifferent_access,
        { timestamp: (now + 1.minute).to_s, containerStopped: { exitStatus: 0 } }.with_indifferent_access
      ],
      pipeline: {
        resources: {
          virtualMachine: {
            machineType: 'n2d-highmem-4',
            bootDiskSizeGb: 300
          }
        }
      }
    }.with_indifferent_access
    mock.expect :metadata, mock_metadata
    mock.expect :metadata, mock_metadata
    mock.expect :metadata, mock_metadata
    mock.expect :error, nil
    mock.expect :done?, true

    cells = @basic_study.expression_matrix_cells(@basic_study_exp_file)
    num_cells = cells.present? ? cells.count : 0

    ApplicationController.life_sciences_api_client.stub :get_pipeline, mock do
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
        machineType: 'n2d-highmem-4',
        bootDiskSizeGb: 300,
        exitStatus: 0
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
        { timestamp: (now + 2.minutes).to_s, containerStopped: { exitStatus: 1 } }
      ],
      pipeline: {
        resources: {
          virtualMachine: {
            machineType: 'n2d-highmem-4',
            bootDiskSizeGb: 300
          }
        }
      }
    }.with_indifferent_access
    mock.expect :metadata, mock_metadata
    mock.expect :metadata, mock_metadata
    mock.expect :metadata, mock_metadata
    mock.expect :error, { code: 1, message: 'mock message' } # simulate error
    mock.expect :done?, true


    ApplicationController.life_sciences_api_client.stub :get_pipeline, mock do
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
    ann_data_file = FactoryBot.create(:ann_data_file, name: 'test.h5ad', study: @basic_study)
    ann_data_file.ann_data_file_info.reference_file = false
    ann_data_file.ann_data_file_info.data_fragments = [
      { _id: BSON::ObjectId.new.to_s, data_type: :cluster, obsm_key_name: 'X_umap', name: 'UMAP' }
    ]
    ann_data_file.upload_file_size = 1.megabyte
    ann_data_file.save
    params_object = AnnDataIngestParameters.new(
      anndata_file: ann_data_file.gs_url, obsm_keys: ann_data_file.ann_data_file_info.obsm_key_names,
      file_size: ann_data_file.upload_file_size
    )
    job = IngestJob.new(
      study: @basic_study, study_file: ann_data_file, user: @user, action: :ingest_anndata, params_object:
    )
    mock = Minitest::Mock.new
    now = DateTime.now.in_time_zone
    mock_metadata = {
      events: [
        { timestamp: now.to_s }.with_indifferent_access,
        { timestamp: (now + 1.minute).to_s, containerStopped: { exitStatus: 0 } }.with_indifferent_access
      ],
      pipeline: {
        resources: {
          virtualMachine: {
            machineType: 'n2d-highmem-4',
            bootDiskSizeGb: 300
          }
        }
      }
    }.with_indifferent_access
    mock.expect :metadata, mock_metadata
    mock.expect :metadata, mock_metadata
    mock.expect :metadata, mock_metadata
    mock.expect :error, nil
    mock.expect :done?, true

    ApplicationController.life_sciences_api_client.stub :get_pipeline, mock do
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
        extractedFileTypes: %w[cluster metadata processed_expression],
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
    job = IngestJob.new(
      study: @basic_study, study_file: reference_file, user: @user, action: :ingest_anndata, params_object:
    )
    mock = Minitest::Mock.new
    now = DateTime.now.in_time_zone
    mock_metadata = {
      events: [
        { timestamp: now.to_s }.with_indifferent_access,
        { timestamp: (now + 1.minute).to_s, containerStopped: { exitStatus: 0 } }.with_indifferent_access
      ],
      pipeline: {
        resources: {
          virtualMachine: {
            machineType: 'n2d-highmem-4',
            bootDiskSizeGb: 300
          }
        }
      }
    }.with_indifferent_access
    mock.expect :metadata, mock_metadata
    mock.expect :metadata, mock_metadata
    mock.expect :metadata, mock_metadata
    mock.expect :error, nil
    mock.expect :done?, true

    ApplicationController.life_sciences_api_client.stub :get_pipeline, mock do
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

  test 'should get ingest summary for AnnData parsing' do
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
    job = IngestJob.new(
      study: @basic_study, study_file: ann_data_file, user: @user, action: :ingest_cluster, params_object:
    )
    now = DateTime.now
    metadata_mock = {
      pipeline: {
        actions: [
          {
            commands: [
              'python', 'ingest_pipeline.py', '--study-id', @basic_study.id.to_s, '--study-file-id',
              ann_data_file.id.to_s, 'ingest_cluster', '--ingest-cluster', '--cluster-file', cluster_file,
              '--name', 'UMAP', '--domain-ranges', '{}'
            ]
          }
        ]
      },
      createTime: (now - 1.minutes).to_default_s,
      startTime: (now - 1.minutes).to_default_s,
      endTime: now.to_default_s
    }.with_indifferent_access

    pipeline_mock = MiniTest::Mock.new
    pipeline_mock.expect :metadata, metadata_mock
    pipeline_mock.expect :metadata, metadata_mock
    pipeline_mock.expect :metadata, metadata_mock
    pipeline_mock.expect :metadata, metadata_mock
    pipeline_mock.expect :error, nil

    operations_mock = Minitest::Mock.new
    operations_mock.expect :operations, [pipeline_mock]

    ApplicationController.life_sciences_api_client.stub :list_pipelines, operations_mock do
      expected_job_props = {
        perfTime: 60000,
        fileName: ann_data_file.name,
        fileType: 'AnnData',
        fileSize: ann_data_file.upload_file_size,
        studyAccession: @basic_study.accession,
        trigger: ann_data_file.upload_trigger,
        jobStatus: 'success',
        numFilesExtracted: 1
      }
      job_props = job.anndata_summary_props
      assert_equal expected_job_props, job_props
      operations_mock.verify
      pipeline_mock.verify
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
    cluster_job = IngestJob.new(
      study: @basic_study, study_file: ann_data_file, user: @user, action: :ingest_cluster,
      params_object: cluster_params_object
    )
    job_mock = Minitest::Mock.new
    job_mock.expect :object, cluster_job

    # negative test
    DelayedJobAccessor.stub :find_jobs_by_handler_type, [Delayed::Job.new] do
      DelayedJobAccessor.stub :dump_job_handler, job_mock do
        metadata_job.report_anndata_summary
        job_mock.verify
        ann_data_file.reload
        assert_not ann_data_file.has_anndata_summary?
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
      numFilesExtracted: 1
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
        end
      end
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
end
