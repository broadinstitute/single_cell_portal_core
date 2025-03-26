require 'test_helper'

class BatchApiClientTest < ActiveSupport::TestCase

  before(:all) do
    @client = ApplicationController.batch_api_client
    @user = FactoryBot.create(:user, test_array: @@users_to_clean)
    @study = FactoryBot.create(:detached_study,
                               name_prefix: 'Batch Client Test',
                               user: @user,
                               test_array: @@studies_to_clean)

    @cluster_file = FactoryBot.create(
      :cluster_file, name: 'UMAP.txt', study: @study,
      cell_input: { x: [1, 2, 3], y: [1, 2, 3], cells: %w[cellA cellB cellC] }
    )
    @ann_data_study = FactoryBot.create(:detached_study,
                                        name_prefix: 'Batch Client AnnData Test',
                                        user: @user,
                                        test_array: @@studies_to_clean)

    @ann_data_file = FactoryBot.create(:ann_data_file,
                                      name: 'matrix.h5ad',
                                      study: @ann_data_study,
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
    @compute_region = BatchApiClient::DEFAULT_COMPUTE_REGION
    @now = DateTime.now.in_time_zone
  end

  test 'should instantiate client and assign attributes' do
    client = BatchApiClient.new
    assert client.project.present?
    assert client.service_account_credentials.present?
    assert client.service.present?
  end

  test 'should get client issuer' do
    issuer = @client.issuer
    assert issuer.match(/gserviceaccount\.com$/)
  end

  test 'should get project and location' do
    location = @client.project_location
    assert location.include?(@client.project)
    assert location.include?(BatchApiClient::DEFAULT_COMPUTE_REGION)
  end

  test 'should list jobs' do
    jobs = @client.list_jobs
    skip 'no jobs in service' if jobs.jobs.blank?
    assert jobs.present?
    assert jobs.jobs.any?
  end

  test 'should get individual job' do
    jobs = @client.list_jobs
    skip 'no jobs in service' if jobs.jobs.blank?
    job_name = jobs.jobs.sample.name
    job = @client.get_job(job_name)
    assert job.present?
    assert job.is_a?(Google::Apis::BatchV1::Job)
  end

  test 'should find matching jobs based on params/state' do
    action = :ingest_anndata
    params_object = AnnDataIngestParameters.new(anndata_file: @ann_data_file.gs_url)
    container = @client.create_container(
      study_file: @ann_data_file, action:, user_metrics_uuid: @user.metrics_uuid, params_object:
    )
    task = @client.create_task_group(action:, machine_type: params_object.machine_type, container:)
    running_job = Google::Apis::BatchV1::Job.new(
      status: Google::Apis::BatchV1::JobStatus.new(state: 'RUNNING'),
      task_groups: [task]
    )
    mock = Minitest::Mock.new
    2.times { mock.expect :jobs, [running_job] }
    @client.stub :list_jobs, mock do
      assert_empty @client.find_matching_jobs(params: params_object.to_options_array) # default is completed states
      found = @client.find_matching_jobs(params: params_object.to_options_array, job_states: BatchApiClient::RUNNING_STATES)
      assert found.size == 1
      assert_equal task, found.first.task_groups.first
    end
  end

  test 'should create and submit Batch API job' do
    action = :ingest_anndata
    params_object = AnnDataIngestParameters.new(anndata_file: @ann_data_file.gs_url)
    mock = Minitest::Mock.new
    mock.expect :authorization=, Google::Auth::ServiceAccountCredentials.new, [
      Google::Auth::ServiceAccountCredentials
    ]
    2.times do
      mock.expect :authorization, Google::Auth::ServiceAccountCredentials.new, []
    end
    mock.expect :create_project_location_job,
                Google::Apis::BatchV1::Job,
                [@client.project_location, Google::Apis::BatchV1::Job], quota_user: @user.id.to_s
    Google::Apis::BatchV1::BatchService.stub :new, mock do
      client = BatchApiClient.new
      client.run_job(study_file: @ann_data_file, user: @user, action:, params_object:)
      mock.verify
    end
  end

  test 'should create and submit DE Batch API job' do
    action = :differential_expression
    bucket_dir = "_scp_internal/anndata_ingest/#{@ann_data_study.accession}_#{@ann_data_file.id}"
    cluster = @ann_data_study.cluster_groups.first
    anndata_options = {
      annotation_name: 'disease',
      annotation_scope: 'study',
      annotation_file: "gs://#{@ann_data_study.bucket_id}/#{bucket_dir}/h5ad_frag.metadata.tsv.gz",
      cluster_file: "gs://#{@ann_data_study.bucket_id}/#{bucket_dir}/h5ad_frag.cluster.X_umap.tsv.gz",
      cluster_name: 'umap',
      cluster_group_id: cluster.id,
      matrix_file_path: @ann_data_file.gs_url,
      matrix_file_type: 'h5ad',
      matrix_file_id: @ann_data_file.id,
      file_size: @ann_data_file.upload_file_size
    }
    params_object = DifferentialExpressionParameters.new(**anndata_options)
    mock = Minitest::Mock.new
    mock.expect :authorization=, Google::Auth::ServiceAccountCredentials.new, [
      Google::Auth::ServiceAccountCredentials
    ]
    2.times do
      mock.expect :authorization, Google::Auth::ServiceAccountCredentials.new, []
    end
    mock.expect :create_project_location_job,
                Google::Apis::BatchV1::Job,
                [@client.project_location, Google::Apis::BatchV1::Job], quota_user: @user.id.to_s
    Google::Apis::BatchV1::BatchService.stub :new, mock do
      client = BatchApiClient.new
      client.run_job(study_file: @ann_data_file, user: @user, action:, params_object:)
      mock.verify
    end
  end

  test 'should indicate if job is done' do
    running_job = Google::Apis::BatchV1::Job.new(status: Google::Apis::BatchV1::JobStatus.new(state: 'RUNNING'))
    success_job = Google::Apis::BatchV1::Job.new(status: Google::Apis::BatchV1::JobStatus.new(state: 'SUCCEEDED'))
    failed_job = Google::Apis::BatchV1::Job.new(status: Google::Apis::BatchV1::JobStatus.new(state: 'FAILED'))
    assert_not @client.job_done?(running_job)
    assert @client.job_done?(success_job)
    assert @client.job_done?(failed_job)
  end

  test 'should get task from existing job' do
    jobs = @client.list_jobs
    skip 'no jobs in service' if jobs.jobs.blank?
    job_name = jobs.jobs.sample.name
    task = @client.get_job_task(job_name)
    assert task.present?
    assert task.is_a?(Google::Apis::BatchV1::Task)
  end

  test 'should get exit code from task' do
    job_name = SecureRandom.uuid
    success = Google::Apis::BatchV1::Task.new(
      status: Google::Apis::BatchV1::TaskStatus.new(
        state: 'SUCCEEDED',
        status_events: [
          Google::Apis::BatchV1::StatusEvent.new(event_time: @now.to_s),
          Google::Apis::BatchV1::StatusEvent.new(event_time: (@now + 1.minute).to_s)
        ]
      )
    )
    @client.stub :get_job_task, success do
      assert_nil @client.exit_code_from_task(job_name)
    end

    failure = Google::Apis::BatchV1::Task.new(
      status: Google::Apis::BatchV1::TaskStatus.new(
        state: 'FAILED',
        status_events: [
          Google::Apis::BatchV1::StatusEvent.new(event_time: @now.to_s),
          Google::Apis::BatchV1::StatusEvent.new(
            event_time: (@now + 1.minute).to_s,
            task_state: 'FAILED',
            task_execution: Google::Apis::BatchV1::TaskExecution.new(exit_code: 137)
          )
        ]
      )
    )
    @client.stub :get_job_task, failure do
      assert_equal 137, @client.exit_code_from_task(job_name)
    end
  end

  test 'should get error from task' do
    job_name = SecureRandom.uuid
    success = Google::Apis::BatchV1::Task.new(
      status: Google::Apis::BatchV1::TaskStatus.new(
        state: 'SUCCEEDED',
        status_events: [
          Google::Apis::BatchV1::StatusEvent.new(event_time: @now.to_s),
          Google::Apis::BatchV1::StatusEvent.new(event_time: (@now + 1.minute).to_s)
        ]
      )
    )
    @client.stub :get_job_task, success do
      assert_nil @client.job_error(job_name)
    end

    failure = Google::Apis::BatchV1::Task.new(
      status: Google::Apis::BatchV1::TaskStatus.new(
        state: 'FAILED',
        status_events: [
          Google::Apis::BatchV1::StatusEvent.new(event_time: @now.to_s),
          Google::Apis::BatchV1::StatusEvent.new(
            event_time: (@now + 1.minute).to_s,
            task_state: 'FAILED',
            task_execution: Google::Apis::BatchV1::TaskExecution.new(exit_code: 137)
          )
        ]
      )
    )
    @client.stub :get_job_task, failure do
      error = @client.job_error(job_name)
      assert error.present?
      assert error.is_a? Google::Apis::BatchV1::StatusEvent
      assert_equal 137, error.task_execution.exit_code
    end
  end

  test 'should get task spec from job' do
    jobs = @client.list_jobs
    skip 'no jobs in service' if jobs.jobs.blank?
    job = jobs.jobs.sample
    spec_from_name = @client.get_job_task_spec(name: job.name)
    spec_from_job = @client.get_job_task_spec(job:)
    assert spec_from_name.present?
    assert spec_from_name.is_a? Google::Apis::BatchV1::TaskSpec
    assert spec_from_job.present?
    assert spec_from_job.is_a? Google::Apis::BatchV1::TaskSpec
  end

  test 'should get job command line' do
    jobs = @client.list_jobs
    skip 'no jobs in service' if jobs.jobs.blank?
    job = jobs.jobs.sample
    commands_from_name = @client.get_job_command_line(name: job.name)
    commands_from_job = @client.get_job_command_line(job:)
    assert commands_from_name.any?
    assert commands_from_name.include? 'ingest_pipeline.py'
    assert commands_from_job.any?
    assert commands_from_job.include? 'ingest_pipeline.py'
    assert_equal commands_from_name, commands_from_job
  end

  test 'should get job environment' do
    jobs = @client.list_jobs
    skip 'no jobs in service' if jobs.jobs.blank?
    job = jobs.jobs.sample
    env_from_name = @client.get_job_environment(name: job.name)
    env_from_job = @client.get_job_environment(job:)
    assert env_from_name.any?
    assert_equal @client.project, env_from_name['GOOGLE_PROJECT_ID']
    assert env_from_job.any?
    assert @client.project, env_from_job['GOOGLE_PROJECT_ID']
    assert_equal env_from_name, env_from_job
  end

  test 'should get job resources' do
    jobs = @client.list_jobs
    skip 'no jobs in service' if jobs.jobs.blank?
    job = jobs.jobs.sample
    resources_from_name = @client.get_job_resources(name: job.name)
    resources_from_job = @client.get_job_resources(job:)
    assert resources_from_name.present?
    assert resources_from_job.present?
    expected_keys = %i[boot_disk_size_gb cpu_milli machine_type memory_mib]
    assert_equal expected_keys, resources_from_name.keys.sort
    assert_equal expected_keys, resources_from_job.keys.sort
  end

  test 'should get log params for job' do
    jobs = @client.list_jobs
    skip 'no jobs in service' if jobs.jobs.blank?
    job = jobs.jobs.sample
    log_params = @client.log_params(job)
    assert log_params.present?
    assert_equal @client.get_job_command_line(job:), log_params.dig(:task, :commands)
    assert_equal BatchApiClient::DEFAULT_COMPUTE_REGION, log_params.dig(:task, :resources, :regions)
  end

  test 'should create task group' do
    action = :ingest_cluster
    machine_type = 'n2d-highmem-8'
    labels = { foo: 'bar' }
    container = @client.create_container(study_file: @cluster_file, action:, user_metrics_uuid: @user.metrics_uuid)
    task_group = @client.create_task_group(action:, machine_type:, container:, labels:)
    assert task_group.is_a? Google::Apis::BatchV1::TaskGroup
    spec = task_group.task_spec
    assert spec.is_a? Google::Apis::BatchV1::TaskSpec
    assert_equal 65536, spec.compute_resource.memory_mib
    assert_equal 8000, spec.compute_resource.cpu_milli
    container = spec.runnables.first.container
    assert container.is_a? Google::Apis::BatchV1::Container
    assert_includes container.commands, @cluster_file.id.to_s
    assert_equal spec.runnables.first.labels, labels
  end

  test 'should create container' do
    action = :ingest_anndata
    params_object = AnnDataIngestParameters.new(anndata_file: @ann_data_file.gs_url)
    container = @client.create_container(
      study_file: @ann_data_file, action:, user_metrics_uuid: @user.metrics_uuid, params_object:
    )
    assert container.is_a? Google::Apis::BatchV1::Container
    assert_equal AdminConfiguration.get_ingest_docker_image, container.image_uri
    assert_equal params_object.to_options_array, (params_object.to_options_array & container.commands)
  end

  test 'should get docker image uri' do
    assert_equal AdminConfiguration.get_ingest_docker_image, @client.image_uri_for_job
    anndata_params = AnnDataIngestParameters.new
    assert_equal AdminConfiguration.get_ingest_docker_image, @client.image_uri_for_job(anndata_params)
    image_params = ImagePipelineParameters.new
    assert_equal Rails.application.config.image_pipeline_docker_image, @client.image_uri_for_job(image_params)
  end

  test 'should create compute resource' do
    machine_type = 'n2d-highmem-16'
    compute = @client.create_compute_resource(machine_type)
    assert_equal 16000, compute.cpu_milli
    assert_equal 131072, compute.memory_mib
  end

  test 'should create allocation policy' do
    instance_policy = @client.create_instance_policy
    labels = { foo: 'bar' }
    allocation = @client.create_allocation_policy(instance_policy:, labels:)
    assert allocation.is_a? Google::Apis::BatchV1::AllocationPolicy
    assert_equal instance_policy, allocation.instances.first.policy
    assert_equal labels, allocation.labels
    assert allocation.network.is_a? Google::Apis::BatchV1::NetworkPolicy
  end

  test 'should create instance policy' do
    policy = @client.create_instance_policy
    assert_equal BatchApiClient::DEFAULT_MACHINE_TYPE, policy.machine_type
    assert_equal 300, policy.boot_disk.size_gb
  end

  test 'should set env vars' do
    env_vars = @client.set_environment_variables
    assert_equal @client.project, env_vars['GOOGLE_PROJECT_ID']
    env_vars = @client.set_environment_variables(action: :image_pipeline)
    assert_equal '0', env_vars['NODE_TLS_REJECT_UNAUTHORIZED']
  end

  test 'should format command line' do
    action = :ingest_anndata
    params_object = AnnDataIngestParameters.new(anndata_file: @ann_data_file.gs_url)
    commands = @client.format_command_line(
      study_file: @ann_data_file, action:, user_metrics_uuid: @user.metrics_uuid, params_object:
    )
    assert_includes commands, '--ingest-anndata'
    assert_includes commands, @ann_data_file.gs_url
    assert_includes commands, @ann_data_file.id.to_s
  end

  test 'should get command line opts' do
    opts = @client.get_command_line_options(@cluster_file, :ingest_cluster)
    assert_includes opts, @cluster_file.name
    assert_includes opts, '--domain-ranges'
  end

  test 'should get machine type' do
    assert_equal BatchApiClient::DEFAULT_MACHINE_TYPE, @client.job_machine_type
    machine_type = 'n2d-highmem-8'
    params_object = AnnDataIngestParameters.new(anndata_file: @ann_data_file.gs_url, machine_type: )
    assert_equal machine_type, @client.job_machine_type(params_object)
  end

  test 'should get job labels' do
    action = :ingest_anndata
    machine_type = 'n2d-highmem-8'
    params_object = AnnDataIngestParameters.new(anndata_file: @ann_data_file.gs_url, machine_type:)
    labels = @client.job_labels(action:, study: @study, study_file: @ann_data_file, user: @user, params_object:)
    assert_equal machine_type, labels[:machine_type]
    assert_equal @study.accession.downcase, labels[:study_accession]
    assert_equal action, labels[:ingest_action]
  end

  test 'should get action label' do
    assert_equal 'ingest_pipeline', @client.label_for_action(:ingest_anndata)
    assert_equal 'differential_expression', @client.label_for_action(:differential_expression)
    assert_equal 'data_cache_pipeline', @client.label_for_action(:render_expression_arrays)
    assert_equal :foo, @client.label_for_action(:foo)
  end

  test 'should sanitize label' do
    label = SecureRandom.alphanumeric(128).downcase
    assert_equal 63, @client.sanitize_label(label).length
    assert_equal 'this_is_sanitized', @client.sanitize_label('THIS IS SANITIZED')
  end

  test 'should parse error message' do
    error_contents = {
      error: 'OOM exception',
      code: 137
    }
    error_msg = 'Job failed'
    mock_error = Minitest::Mock.new
    mock_error.expect :body, error_contents.to_json
    mock_error.expect :message, error_msg
    expected_message = "#{error_msg} (#{error_contents['code']}): #{error_contents['message']}"
    assert_equal @client.parse_error_message(mock_error), expected_message
    standard_error = RuntimeError.new('this is the error')
    assert_equal 'RuntimeError: this is the error', @client.parse_error_message(standard_error)
  end
end
