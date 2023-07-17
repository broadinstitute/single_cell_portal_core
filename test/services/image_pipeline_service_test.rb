require 'test_helper'

class ImagePipelineServiceTest < ActiveSupport::TestCase
  before(:all) do
    @user = FactoryBot.create(:api_user, test_array: @@users_to_clean)
    @study = FactoryBot.create(:detached_study,
                               name_prefix: 'ImagePipelineService Test',
                               user: @user,
                               test_array: @@studies_to_clean)

    @dense_matrix = FactoryBot.create(:expression_file,
                                      name: 'expression.txt',
                                      study: @study,
                                      expression_file_info: {
                                        is_raw_counts: false,
                                        library_preparation_protocol: 'Drop-seq',
                                        biosample_input_type: 'Whole cell',
                                        modality: 'Proteomic'
                                      },
                                      upload_file_size: 10.megabytes)
    @pten_gene = FactoryBot.create(:gene_with_expression,
                                   name: 'PTEN',
                                   study_file: @dense_matrix,
                                   expression_input: [['A', 0],['B', 3],['C', 1.5]])
    @cluster_file = FactoryBot.create(:cluster_file,
                                      name: 'cluster.txt',
                                      study: @study)
    @sparse_matrix = FactoryBot.create(:expression_file,
                                       name: 'matrix.mtx',
                                       file_type: 'MM Coordinate Matrix',
                                       study: @study,
                                       expression_file_info: {
                                         is_raw_counts: false,
                                         library_preparation_protocol: 'Drop-seq',
                                         biosample_input_type: 'Whole cell',
                                         modality: 'Proteomic'
                                       },
                                       status: 'uploaded', # gotcha for bundling
                                       upload_file_size: 10.megabytes)
    @genes_file = FactoryBot.create(:study_file,
                                    name: 'genes.tsv',
                                    study: @study,
                                    status: 'uploaded',
                                    file_type: '10X Genes File')
    @barcodes_file = FactoryBot.create(:study_file,
                                       name: 'barcodes.tsv',
                                       study: @study,
                                       status: 'uploaded',
                                       file_type: '10X Barcodes File')
    # create bundle so that validations will pass
    bundle = StudyFileBundle.new(bundle_type: 'MM Coordinate Matrix', study: @study)
    bundle.add_files(@sparse_matrix, @genes_file, @barcodes_file)
  end

  test 'should launch image pipeline job' do
    job_mock = Minitest::Mock.new
    job_mock.expect(:push_remote_and_launch_ingest, Delayed::Job.new)
    mock = Minitest::Mock.new
    mock.expect(:delay, job_mock)
    IngestJob.stub :new, mock do
      ApplicationController.firecloud_client.stub :workspace_file_exists?, true do
        ImagePipelineService.run_image_pipeline_job(@study, @cluster_file, data_cache_perftime: 120_000)
      end
    end
  end

  test 'should launch render expression arrays job for all matrix types' do
    [@dense_matrix, @sparse_matrix].each do |matrix_file|
      job_mock = Minitest::Mock.new
      job_mock.expect(:push_remote_and_launch_ingest, Delayed::Job.new)
      mock = Minitest::Mock.new
      mock.expect(:delay, job_mock)
      IngestJob.stub :new, mock do
        ApplicationController.firecloud_client.stub :workspace_file_exists?, true do
          job_launched = ImagePipelineService.run_render_expression_arrays_job(@study, @cluster_file, matrix_file)
          assert job_launched, "failed to launch job for #{matrix_file.name} (#{matrix_file.file_type})"
          mock.verify
          job_mock.verify
        end
      end
    end
  end

  test 'should validate parameters for images pipeline jobs' do
    # wrong data types
    assert_raise ArgumentError do
      ImagePipelineService.run_image_pipeline_job({}, {})
    end

    # passing matrix as cluster file
    assert_raise ArgumentError do
      ImagePipelineService.run_image_pipeline_job(@study, @dense_matrix)
    end

    # should fail because file is not in bucket
    assert_raise ArgumentError do
      ImagePipelineService.run_image_pipeline_job(@study, @cluster_file)
    end
  end

  test 'should validate parameters for expression array jobs' do
    # wrong data types
    assert_raise ArgumentError do
      ImagePipelineService.run_render_expression_arrays_job({}, {}, {})
    end

    # passing matrix as cluster file
    assert_raise ArgumentError do
      ImagePipelineService.run_render_expression_arrays_job(@study, @dense_matrix, @cluster_file)
    end

    # should fail because file is not in bucket
    # use mock to suppress error logging
    assert_raise ArgumentError do
      mock = Minitest::Mock.new
      mock.expect :workspace_file_exists?, false, [String, String]
      ApplicationController.stub :firecloud_client, mock do
        ImagePipelineService.run_render_expression_arrays_job(@study, @cluster_file, @dense_matrix)
      end
    end
  end

  test 'should create image pipeline parameters object' do
    ApplicationController.firecloud_client.stub :workspace_file_exists?, true do
      params = ImagePipelineService.create_image_pipeline_parameters_object(@study, @cluster_file, 120_000)
      assert params.valid?
      assert_equal @cluster_file.name, params.cluster
      assert_equal @study.bucket_id, params.bucket
      assert_equal @study.accession, params.accession
      assert_equal Rails.env.to_s, params.environment
      assert_equal 7, params.cores
      assert_equal ImagePipelineParameters::PARAM_DEFAULTS[:docker_image], params.docker_image
    end
  end

  test 'should create expression array parameters object' do
    [@dense_matrix, @sparse_matrix].each do |matrix_file|
      ApplicationController.firecloud_client.stub :workspace_file_exists?, true do
        params = ImagePipelineService.create_expression_parameters_object(@cluster_file, matrix_file)
        assert params.valid?, "failed to validate parameters for #{matrix_file.name} (#{matrix_file.file_type})"
        assert_equal params.cluster_file, @cluster_file.gs_url
        assert_equal params.matrix_file_path, matrix_file.gs_url
        assert_equal RenderExpressionArraysParameters::MACHINE_TYPES[:medium], params.machine_type
        expected_matrix_type = matrix_file.file_type == 'Expression Matrix' ? 'dense' : 'mtx'
        assert_equal expected_matrix_type, params.matrix_file_type
      end
    end
  end
end
