require 'test_helper'

class DifferentialExpressionServiceTest < ActiveSupport::TestCase

  before(:all) do
    @user = FactoryBot.create(:api_user, test_array: @@users_to_clean)
    @basic_study = FactoryBot.create(:detached_study,
                                     name_prefix: 'DifferentialExpressionService Test',
                                     user: @user,
                                     test_array: @@studies_to_clean)

    @cells = %w[A B C D E]
    @raw_matrix = FactoryBot.create(:expression_file,
                                   name: 'raw.txt',
                                   study: @basic_study,
                                   expression_file_info: {
                                     is_raw_counts: true,
                                     units: 'raw counts',
                                     library_preparation_protocol: 'Drop-seq',
                                     biosample_input_type: 'Whole cell',
                                     modality: 'Proteomic'
                                   })
    @cluster_file = FactoryBot.create(:cluster_file,
                                     name: 'cluster_diffexp.txt',
                                     study: @basic_study,
                                     cell_input: {
                                       x: [1, 4, 6, 8, 9],
                                       y: [7, 5, 3, 2, 1],
                                       cells: @cells
                                     },
                                     annotation_input: [
                                       {
                                         name: 'foo', type: 'group', values: %w[bar bar baz baz baz],
                                         is_differential_expression_enabled: false
                                       }
                                     ])
    @cluster_group = @basic_study.cluster_groups.by_name('cluster_diffexp.txt')
    FactoryBot.create(:metadata_file,
                      name: 'metadata.txt',
                      study: @basic_study,
                      cell_input: @cells,
                      annotation_input: [
                        {
                          name: 'cell_type__ontology_label',
                          type: 'group',
                          values: ['B cell', 'B cell', 'T cell', 'B cell', 'T cell']
                        },
                        {
                          name: 'cell_type',
                          type: 'group',
                          values: %w[CL_0000236 CL_0000236 CL_0000084 CL_0000236 CL_0000084]
                        },
                        {
                          name: 'seurat_clusters',
                          type: 'group',
                          values: %w[1 1 2 1 2]
                        },
                        { name: 'species', type: 'group', values: %w[dog cat dog dog cat] },
                        { name: 'disease', type: 'group', values: %w[none none measles measles measles] }
                      ])
    @job_params = {
      annotation_name: 'species',
      annotation_scope: 'study'
    }
    @basic_study.update(initialized: true)

    # parameters for creating "all cells" array, since this needs to be created/destroyed after every run
    @all_cells_array_params = {
      name: 'raw.txt Cells', array_type: 'cells', linear_data_type: 'Study', study_id: @basic_study.id,
      cluster_name: 'raw.txt', array_index: 0, linear_data_id: @basic_study.id, study_file_id: @raw_matrix.id,
      cluster_group_id: nil, subsample_annotation: nil, subsample_threshold: nil, values: @cells
    }
  end

  teardown do
    DataArray.find_by(@all_cells_array_params)&.destroy
    @basic_study.differential_expression_results.destroy_all
    StudyFile.where(file_type: 'Differential Expression').delete_all
    @basic_study.public = true
    @basic_study.save(validate: false) # skip callbacks for performance
  end

  test 'should validate parameters and launch differential expression job' do
    # should fail on annotation missing
    assert_raise ArgumentError do
      DifferentialExpressionService.run_differential_expression_job(
        @cluster_group, @basic_study, @user, annotation_name: 'NA', annotation_scope: 'study'
      )
    end

    # should fail on cell validation
    assert_raise ArgumentError do
      DifferentialExpressionService.run_differential_expression_job(@cluster_group, @basic_study, @user, **@job_params)
    end
    # test launch by manually creating expression matrix cells array for validation
    DataArray.create!(@all_cells_array_params)

    # we need to mock 2 levels deep as :delay should yield the :push_remote_and_launch_ingest mock
    job_mock = Minitest::Mock.new
    job_mock.expect(:push_remote_and_launch_ingest, Delayed::Job.new)
    mock = Minitest::Mock.new
    mock.expect(:delay, job_mock)
    ApplicationController.batch_api_client.stub :find_matching_jobs, [] do
      IngestJob.stub :new, mock do
        job_launched = DifferentialExpressionService.run_differential_expression_job(
          @cluster_group, @basic_study, @user, **@job_params
        )
        assert job_launched
        mock.verify
        job_mock.verify
      end
    end

    # test pairwise job
    @job_params[:de_type] = 'pairwise'
    @job_params[:group1] = 'dog'
    @job_params[:group2] = 'cat'

    job_mock = Minitest::Mock.new
    job_mock.expect(:push_remote_and_launch_ingest, Delayed::Job.new)
    mock = Minitest::Mock.new
    mock.expect(:delay, job_mock)
    ApplicationController.batch_api_client.stub :find_matching_jobs, [] do
      IngestJob.stub :new, mock do
        job_launched = DifferentialExpressionService.run_differential_expression_job(
          @cluster_group, @basic_study, @user, **@job_params
        )
        assert job_launched
        mock.verify
        job_mock.verify
      end
    end
  end

  test 'should run differential expression job with sparse matrix' do
    study = FactoryBot.create(:detached_study,
                              name_prefix: 'Sparse DE Test',
                              user: @user,
                              test_array: @@studies_to_clean)

    cells = %w[Cell_A Cell_B Cell_C Cell_D Cell_E]
    matrix = FactoryBot.create(:study_file,
                               name: 'raw.txt',
                               study: study,
                               file_type: 'MM Coordinate Matrix',
                               parse_status: 'parsed',
                               status: 'uploaded',
                               expression_file_info: {
                                 is_raw_counts: true,
                                 units: 'raw counts',
                                 library_preparation_protocol: 'Drop-seq',
                                 biosample_input_type: 'Whole cell',
                                 modality: 'Proteomic'
                               })

    genes = FactoryBot.create(:study_file,
                              name: 'genes.txt',
                              study: study,
                              status: 'uploaded',
                              file_type: '10X Genes File')

    barcodes = FactoryBot.create(:study_file,
                                 name: 'barcodes.txt',
                                 study: study,
                                 status: 'uploaded',
                                 file_type: '10X Barcodes File')

    bundle = StudyFileBundle.new(study: study, bundle_type: matrix.file_type)
    bundle.add_files(matrix, genes, barcodes)
    bundle.save!
    cluster_file = FactoryBot.create(:cluster_file,
                                    name: 'cluster_diffexp.txt',
                                    study: study,
                                    cell_input: {
                                      x: [1, 4, 6, 7, 9],
                                      y: [7, 5, 3, 4, 5],
                                      cells: cells
                                    })
    cluster_group = study.cluster_groups.by_name('cluster_diffexp.txt')
    FactoryBot.create(:metadata_file,
                      name: 'metadata.txt',
                      study: study,
                      cell_input: cells,
                      annotation_input: [
                        { name: 'species', type: 'group', values: %w[dog cat dog dog cat] },
                        { name: 'disease', type: 'group', values: %w[none none measles measles measles] }
                      ])
    annotation = {
      annotation_name: 'species',
      annotation_scope: 'study'
    }

    data_array_params = {
      name: 'raw.txt Cells', array_type: 'cells', linear_data_type: 'Study', study_id: study.id,
      cluster_name: 'raw.txt', array_index: 0, linear_data_id: study.id, study_file_id: matrix.id,
      cluster_group_id: nil, subsample_annotation: nil, subsample_threshold: nil, values: cells
    }
    DataArray.create(data_array_params)

    job_mock = Minitest::Mock.new
    job_mock.expect(:push_remote_and_launch_ingest, Delayed::Job.new)
    mock = Minitest::Mock.new
    mock.expect(:delay, job_mock)
    ApplicationController.batch_api_client.stub :find_matching_jobs, [] do
      IngestJob.stub :new, mock do
        job_launched = DifferentialExpressionService.run_differential_expression_job(
          cluster_group, study, @user, **annotation
        )
        assert job_launched
        mock.verify
        job_mock.verify
      end
    end
  end

  test 'should run differential expression job on study defaults' do
    # test validation
    @basic_study.update(default_options: {})
    assert_raise ArgumentError do
      DifferentialExpressionService.run_differential_expression_job(@cluster_group, @basic_study, @user, **@job_params)
    end

    @basic_study.update(default_options: { cluster: 'cluster_diffexp.txt', annotation: 'species--group--study' })
    DataArray.create!(@all_cells_array_params)
    job_mock = Minitest::Mock.new
    job_mock.expect(:push_remote_and_launch_ingest, Delayed::Job.new)
    mock = Minitest::Mock.new
    mock.expect(:delay, job_mock)
    ApplicationController.batch_api_client.stub :find_matching_jobs, [] do
      IngestJob.stub :new, mock do
        job_launched = DifferentialExpressionService.run_differential_expression_on_default(@basic_study.accession)
        assert job_launched
        mock.verify
        job_mock.verify
      end
    end
  end

  test 'should not run differential expression job if dry run' do
    DataArray.create!(@all_cells_array_params)
    params = {
      annotation_name: 'species',
      annotation_scope: 'study',
      dry_run: true
    }

    job_requested = DifferentialExpressionService.run_differential_expression_job(
      @cluster_group, @basic_study, @user, **params
    )
    assert job_requested
    assert_equal [], DelayedJobAccessor.find_jobs_by_handler_type(IngestJob, @cluster_file)
  end

  test 'should run differential expression job on all eligible annotations' do
    DataArray.create!(@all_cells_array_params)
    job_mock_one = Minitest::Mock.new
    job_mock_two = Minitest::Mock.new
    job_mock_one.expect(:push_remote_and_launch_ingest, Delayed::Job.new)
    job_mock_two.expect(:push_remote_and_launch_ingest, Delayed::Job.new)
    mock = Minitest::Mock.new
    mock.expect(:delay, job_mock_one)
    mock.expect(:delay, job_mock_two)
    # cell_type__ontology_label and seurat_clusters should be marked as eligible
    ApplicationController.batch_api_client.stub :find_matching_jobs, [] do
      IngestJob.stub :new, mock do
        jobs_launched = DifferentialExpressionService.run_differential_expression_on_all(@basic_study.accession)
        assert_equal 2, jobs_launched
        mock.verify
        job_mock_one.verify
        job_mock_two.verify
      end
    end
  end

  test 'should find existing DE results' do
    cluster = @basic_study.cluster_groups.by_name(@cluster_file.name)
    annotation = { annotation_name: 'cell_type__ontology_label', annotation_scope: 'study' }
    result = DifferentialExpressionResult.create(
      study: @basic_study, cluster_group: cluster, matrix_file_id: @raw_matrix.id, cluster_name: cluster.name,
      annotation_name: 'cell_type__ontology_label', annotation_scope: 'study', computational_method: 'wilcoxon',
      one_vs_rest_comparisons: ['B cell', 'T cell']
    )
    assert result.present?
    @basic_study.reload
    assert DifferentialExpressionService.results_exist?(@basic_study, annotation)
    no_results = { annotation_name: 'foo', annotation_scope: 'cluster', cluster_group_id: cluster.id }
    assert_not DifferentialExpressionService.results_exist?(@basic_study, no_results)
  end

  test 'should find eligible annotations' do
    cell_type = { annotation_name: 'cell_type__ontology_label', annotation_scope: 'study' }
    seurat = { annotation_name: 'seurat_clusters', annotation_scope: 'study' }
    eligible_annotations = DifferentialExpressionService.find_eligible_annotations(@basic_study)
    assert_equal 2, eligible_annotations.count
    assert_includes eligible_annotations, cell_type
    assert_includes eligible_annotations, seurat
  end

  test 'should determine study eligibility' do
    assert DifferentialExpressionService.study_eligible?(@basic_study)
    # ensure private studies still qualify
    @basic_study.public = true
    @basic_study.save(validate: false) # skip callbacks for performance
    @basic_study.reload
    assert DifferentialExpressionService.study_eligible?(@basic_study)
    empty_study = FactoryBot.create(:detached_study,
                                    name_prefix: 'Empty Test',
                                    user: @user,
                                    test_array: @@studies_to_clean)
    assert_not DifferentialExpressionService.study_eligible?(empty_study)
  end

  test 'should not mark studies with author DE as eligible' do
    assert DifferentialExpressionService.study_eligible?(@basic_study)
    FactoryBot.create(:differential_expression_file,
                      study: @basic_study,
                      name: 'author_de.tsv',
                      cluster_group: @basic_study.cluster_groups.first,
                      annotation_name: 'cell_type__ontology_label',
                      annotation_scope: 'group',
                      computational_method: 'wilcoxon')
    assert_not DifferentialExpressionService.study_eligible?(@basic_study)
  end

  test 'should determine annotation eligibility by name' do
    %w[cell_type cell_type__ontology_label clust clustering seurat leiden louvain snn_res].each do |name|
      assert DifferentialExpressionService.annotation_eligible?(name)
      assert DifferentialExpressionService.annotation_eligible?(name.upcase)
      assert DifferentialExpressionService.annotation_eligible?(name.capitalize)
    end
    disallowed = 'enrichment__cell_type'
    assert_not DifferentialExpressionService.annotation_eligible?(disallowed)
    assert_not DifferentialExpressionService.annotation_eligible?(disallowed.upcase)
    assert_not DifferentialExpressionService.annotation_eligible?(disallowed.capitalize)
  end

  test 'should backfill new annotations' do
    # create existing result to ensure this is not regenerated
    DataArray.create!(@all_cells_array_params)
    cluster = @basic_study.cluster_groups.by_name(@cluster_file.name)
    annotation = { annotation_name: 'cell_type__ontology_label', annotation_scope: 'study' }
    DifferentialExpressionResult.create(
      study: @basic_study, cluster_group: cluster, matrix_file_id: @raw_matrix.id, cluster_name: cluster.name,
      annotation_name: annotation[:annotation_name], annotation_scope: annotation[:annotation_scope],
      computational_method: 'wilcoxon', one_vs_rest_comparisons: ['B cell', 'T cell']
    )

    @basic_study.reload
    job_mock = Minitest::Mock.new
    job_mock.expect(:push_remote_and_launch_ingest, Delayed::Job.new)
    mock = Minitest::Mock.new
    mock.expect(:delay, job_mock)
    ApplicationController.batch_api_client.stub :find_matching_jobs, [] do
      IngestJob.stub :new, mock do
        # restrict to this study to prevent any dangling studies being picked up
        stats = DifferentialExpressionService.backfill_new_results(study_accessions: [@basic_study.accession])
        assert_equal 1, stats[:total_jobs]
        assert_equal 1, stats[@basic_study.accession]
        mock.verify
        job_mock.verify
      end
    end
  end

  test 'should launch DE job for single AnnData file' do
    study = FactoryBot.create(:detached_study,
                              name_prefix: 'AnnData DE Test',
                              user: @user,
                              test_array: @@studies_to_clean)

    cells = 'A'.upto('H').map { |c| "cell#{c}"}
    genes = %w[gad1 gad2 phex farsa cldn4 sox1 itm2a sergef]
    expression_input = genes.index_with(cells.map {|c| [c, rand.floor(3)]})
    annotation_input = [{ name: 'louvain', type: 'group', values: %w(0 0 0 1 1 1 2 2) }]
    coordinate_input = [
      { 'umap' => { x: 1.upto(8).to_a, y: 8.downto(1).to_a } }
    ]
    ann_data_file = FactoryBot.create(:ann_data_file,
                                      study:,
                                      name: 'test.h5ad',
                                      reference_file: false,
                                      cell_input: cells,
                                      expression_input:,
                                      annotation_input:,
                                      coordinate_input:)
    ann_data_file.expression_file_info.update(is_raw_counts: true)
    ann_data_file.ann_data_file_info.update(has_raw_counts: true)
    ann_data_file.save
    ann_data_file.reload
    job_mock = Minitest::Mock.new
    job_mock.expect(:push_remote_and_launch_ingest, Delayed::Job.new)
    mock = Minitest::Mock.new
    mock.expect(:delay, job_mock)
    # cell_type__ontology_label and seurat_clusters should be marked as eligible
    ApplicationController.batch_api_client.stub :find_matching_jobs, [] do
      IngestJob.stub :new, mock do
        jobs_launched = DifferentialExpressionService.run_differential_expression_on_all(study.accession)
        assert_equal 1, jobs_launched
        mock.verify
        job_mock.verify
      end
    end
  end

  test 'should skip launching DE job if matching running job found' do
    running_job = Google::Apis::BatchV1::Job.new(
      name: 'running-de-job',
      status: Google::Apis::BatchV1::JobStatus.new(state: 'RUNNING')
    )
    DataArray.create!(@all_cells_array_params)
    ApplicationController.batch_api_client.stub :find_matching_jobs, [running_job] do
      assert_not DifferentialExpressionService.run_differential_expression_job(
        @cluster_group, @basic_study, @user, **@job_params
      )
    end
  end

  test 'should get weekly DE quota value' do
    default_value = DifferentialExpressionService::DEFAULT_USER_QUOTA
    assert_equal default_value, DifferentialExpressionService.get_weekly_user_quota
    # test config override
    config = AdminConfiguration.create!(config_type: 'Weekly User DE Quota', value_type: 'Numeric', value: '10')
    assert_equal config.value.to_i, DifferentialExpressionService.get_weekly_user_quota
    config.destroy
    assert_equal default_value, DifferentialExpressionService.get_weekly_user_quota
  end

  test 'should check weekly user DE quota' do
    user = FactoryBot.create(:api_user, test_array: @@users_to_clean)
    assert_not DifferentialExpressionService.job_exceeds_quota?(user)
    user.update(weekly_de_quota: DifferentialExpressionService::DEFAULT_USER_QUOTA)
    assert DifferentialExpressionService.job_exceeds_quota?(user)
  end

  test 'should increment user DE quota' do
    user = FactoryBot.create(:api_user, weekly_de_quota: 1, test_array: @@users_to_clean)
    DifferentialExpressionService.increment_user_quota(user)
    user.reload
    assert_equal 2, user.weekly_de_quota
  end

  test 'should reset user DE quotas' do
    user = FactoryBot.create(:api_user, weekly_de_quota: 1, test_array: @@users_to_clean)
    DifferentialExpressionService.reset_all_user_quotas
    user.reload
    assert_equal 0, user.weekly_de_quota
  end
end
