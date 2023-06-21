require 'test_helper'

# tests for creating various Google Life Sciences API objects and submitting/getting running pipelines
class LifeSciencesApiClientTest < ActiveSupport::TestCase

  before(:all) do
    @client = ApplicationController.life_sciences_api_client
    @user = FactoryBot.create(:user, test_array: @@users_to_clean)
    @study = FactoryBot.create(:detached_study,
                               name_prefix: 'Papi Client Test',
                               user: @user,
                               test_array: @@studies_to_clean)

    @expression_matrix = FactoryBot.create(:study_file, name: 'dense.txt', file_type: 'Expression Matrix', study: @study)

    @expression_matrix.build_expression_file_info(is_raw_counts: true, units: 'raw counts',
                                                  library_preparation_protocol: 'MARS-seq',
                                                  modality: 'Transcriptomic: unbiased',
                                                  biosample_input_type: 'Whole cell')
    @expression_matrix.save!
    @cluster_file = FactoryBot.create(:cluster_file,
                                      name: 'cluster.txt', study: @study,
                                      cell_input: {
                                        x: [1, 4, 6],
                                        y: [7, 5, 3],
                                        z: [2, 8, 9],
                                        cells: %w[A B C]
                                      },
                                      x_axis_label: 'PCA 1',
                                      y_axis_label: 'PCA 2',
                                      z_axis_label: 'PCA 3',
                                      cluster_type: '3d',
                                      x_axis_min: -1,
                                      x_axis_max: 1,
                                      y_axis_min: -2,
                                      y_axis_max: 2,
                                      z_axis_min: -3,
                                      z_axis_max: 3,
                                      annotation_input: [
                                        { name: 'Category', type: 'group', values: %w[bar bar baz] },
                                        { name: 'Intensity', type: 'numeric', values: [1.1, 2.2, 3.3] }
                                      ])
    @compute_region = LifeSciencesApiClient::DEFAULT_COMPUTE_REGION
  end

  test 'should instantiate client and assign attributes' do
    client = LifeSciencesApiClient.new
    assert client.project.present?
    assert client.service_account_credentials.present?
    assert client.service.present?
  end

  test 'should get client issuer' do
    issuer = @client.issuer
    assert issuer.match(/gserviceaccount\.com$/)
  end

  test 'should get project number and location' do
    location = @client.project_location
    assert location.include?(@client.project_number)
    assert location.include?(LifeSciencesApiClient::DEFAULT_COMPUTE_REGION)
  end

  test 'should list pipelines' do
    pipelines = @client.list_pipelines
    skip 'could not find any pipelines' if pipelines.operations.blank?
    assert pipelines.present?
    assert pipelines.operations.any?
  end

  test 'should assemble pipeline parameters and submit job' do
    # only tests interface to pipeline submission, will not actually submit a job
    mock = Minitest::Mock.new
    mock.expect :authorization=, Google::Auth::ServiceAccountCredentials.new, [
      Google::Auth::ServiceAccountCredentials
    ]
    mock.expect :authorization, Google::Auth::ServiceAccountCredentials.new, []
    mock.expect :run_pipeline, Google::Apis::LifesciencesV2beta::Operation.new, [
      Google::Apis::LifesciencesV2beta::RunPipelineRequest, { quota_user: @user.id.to_s }
    ]
    Google::Apis::LifesciencesV2beta::CloudLifeSciencesService.stub :new, mock do
      client = LifeSciencesApiClient.new
      client.run_pipeline(study_file: @expression_matrix, user: @user, action: :ingest_expression)
      mock.verify
    end

    # test DE submission
    mock = Minitest::Mock.new
    mock.expect :authorization=, Google::Auth::ServiceAccountCredentials.new, [
      Google::Auth::ServiceAccountCredentials
    ]
    mock.expect :authorization, Google::Auth::ServiceAccountCredentials.new, []
    mock.expect :run_pipeline, Google::Apis::LifesciencesV2beta::Operation.new, [
      Google::Apis::LifesciencesV2beta::RunPipelineRequest, { quota_user: @user.id.to_s }
    ]
    Google::Apis::LifesciencesV2beta::CloudLifeSciencesService.stub :new, mock do
      client = LifeSciencesApiClient.new
      de_opts = {
        annotation_name: 'Category',
        annotation_scope: 'cluster',
        annotation_file: @cluster_file.gs_url,
        cluster_file: @cluster_file.gs_url,
        cluster_name: 'cluster.txt',
        matrix_file_path: @expression_matrix.gs_url,
        matrix_file_type: 'dense'
      }
      de_params = DifferentialExpressionParameters.new(de_opts)
      client.run_pipeline(study_file: @cluster_file, user: @user, action: :differential_expression,
                          params_object: de_params)
      mock.verify
    end
  end

  test 'should get individual pipeline run' do
    pipelines = @client.list_pipelines
    skip 'could not find any pipelines' if pipelines.operations.blank?
    pipeline = pipelines.operations.sample
    requested_pipeline = @client.get_pipeline(name: pipeline.name)
    assert_equal pipeline.name, requested_pipeline.name
    assert_equal pipeline.metadata.dig('pipeline', 'actions'), requested_pipeline.metadata.dig('pipeline', 'actions')
  end

  test 'should set env vars for pipeline' do
    env_vars = @client.set_environment_variables
    assert env_vars.keys.include? 'DATABASE_HOST'
    assert env_vars.keys.include? 'MONGODB_USERNAME'
    assert env_vars.keys.include? 'GOOGLE_PROJECT_ID'
    assert_equal @client.project, env_vars['GOOGLE_PROJECT_ID']
    image_pipeline_vars = @client.set_environment_variables(action: :image_pipeline)
    assert_equal '0', image_pipeline_vars['NODE_TLS_REJECT_UNAUTHORIZED']
    assert_includes image_pipeline_vars.keys, 'STAGING_INTERNAL_IP'
  end

  test 'should create virtual machine config' do
    vm = @client.create_virtual_machine_object
    assert vm.is_a? Google::Apis::LifesciencesV2beta::VirtualMachine
    # create different machine type
    machine_type = 'n2-standard-4'
    n2_vm = @client.create_virtual_machine_object(machine_type:, boot_disk_size_gb: 10, preemptible: true)
    assert n2_vm.is_a? Google::Apis::LifesciencesV2beta::VirtualMachine
    assert_equal machine_type, n2_vm.machine_type
    assert_equal 10, n2_vm.boot_disk_size_gb
    assert n2_vm.preemptible
  end

  test 'should create resources object' do
    regions = [@compute_region]
    resources = @client.create_resources_object(regions:)
    assert resources.is_a? Google::Apis::LifesciencesV2beta::Resources
    assert_equal regions, resources.regions
    # try overriding default VM
    machine_type = 'n2-standard-4'
    n2_vm = @client.create_virtual_machine_object(machine_type:)
    n2_resources = @client.create_resources_object(regions:, vm: n2_vm)
    assert_equal n2_vm, n2_resources.virtual_machine
  end

  test 'should construct command line for pipeline jobs by file_type' do
    user_metrics_uuid = @user.metrics_uuid
    exp_cmd = @client.get_command_line(study_file: @expression_matrix, action: :ingest_expression, user_metrics_uuid:)
    assert exp_cmd.any?
    assert exp_cmd.include? @study.id.to_s
    assert exp_cmd.include? @expression_matrix.id.to_s
    assert exp_cmd.include? user_metrics_uuid
    assert exp_cmd.include? '--matrix-file'
    assert exp_cmd.include? @expression_matrix.gs_url
    assert exp_cmd.include? '--matrix-file-type'
    assert exp_cmd.include? 'dense'

    cluster_cmd = @client.get_command_line(study_file: @cluster_file, action: :ingest_cluster, user_metrics_uuid:)
    assert cluster_cmd.any?
    assert cluster_cmd.include? @study.id.to_s
    assert cluster_cmd.include? @cluster_file.id.to_s
    assert cluster_cmd.include? '--cluster-file'
    assert cluster_cmd.include? @cluster_file.gs_url
    assert cluster_cmd.include? user_metrics_uuid
    assert cluster_cmd.include? '--ingest-cluster'

    # user-uploaded DE file
    cluster_group = @study.cluster_groups.first
    annotation_name = 'Category'
    annotation_scope = 'cluster'
    de_file = @study.study_files.build(file_type: 'Differential Expression', upload_file_name: 'de.tsv')
    de_file.build_differential_expression_file_info(annotation_name:, annotation_scope:, cluster_group:)
    de_cmd = @client.get_command_line(study_file: de_file, action: :ingest_differential_expression, user_metrics_uuid:)
    assert de_cmd.any?
    assert de_cmd.include? de_file.id.to_s
    assert de_cmd.include? '--differential-expression-file'
    assert de_cmd.include? de_file.gs_url
    assert de_cmd.include? '--annotation-name'
    assert de_cmd.include? annotation_name
    assert de_cmd.include? '--annotation-scope'
    assert de_cmd.include? annotation_scope
    assert de_cmd.include? '--cluster-name'
    assert de_cmd.include? cluster_group.name
    assert de_cmd.include? '--computational-method'
    assert de_cmd.include? DifferentialExpressionResult::DEFAULT_COMP_METHOD
    assert de_cmd.include? '--ingest-differential-expression'
  end

  test 'should get extra command line options' do
    cluster_cmd = @client.get_command_line(study_file: @cluster_file, action: :ingest_cluster,
                                           user_metrics_uuid: @user.metrics_uuid)
    assert cluster_cmd.include? '--domain-ranges'
    sanitized_domains = "{'x':[-1,1],'y':[-2,2],'z':[-3,3]}"
    assert cluster_cmd.include? sanitized_domains
  end

  # this test covers many sub-methods that are required to create a pipeline request, such as creating resources,
  # environment, actions, and pipelines objects
  test 'should create pipelines request object' do
    exp_cmd = @client.get_command_line(study_file: @expression_matrix, action: :ingest_expression,
                                       user_metrics_uuid: @user.metrics_uuid)
    environment = @client.set_environment_variables
    actions = @client.create_actions_object(commands: exp_cmd, environment:)
    regions = [@compute_region]
    resources = @client.create_resources_object(regions:)
    pipeline = @client.create_pipeline_object(actions:, environment:, resources:)
    labels = { foo: 'bar' }
    pipeline_request = @client.create_run_pipeline_request_object(pipeline:, labels:)
    assert pipeline_request.is_a? Google::Apis::LifesciencesV2beta::RunPipelineRequest
    assert_equal pipeline, pipeline_request.pipeline
    assert_equal actions, pipeline_request.pipeline.actions
    assert_equal environment, pipeline_request.pipeline.environment
    assert_equal resources, pipeline_request.pipeline.resources
    assert_equal exp_cmd, pipeline_request.pipeline.actions.commands
  end

  test 'should create pipeline request object for differential expression job' do
    # test DE handling of custom VMs
    de_opts = {
      annotation_name: 'Category',
      annotation_scope: 'cluster',
      annotation_file: @cluster_file.gs_url,
      cluster_file: @cluster_file.gs_url,
      cluster_name: 'cluster.txt',
      matrix_file_path: @expression_matrix.gs_url,
      matrix_file_type: 'dense',
      machine_type: 'n1-highmem-16'
    }
    de_params = DifferentialExpressionParameters.new(de_opts)
    de_cmd = @client.get_command_line(study_file: @cluster_file, action: :differential_expression,
                                      user_metrics_uuid: @user.metrics_uuid, params_object: de_params)
    environment = @client.set_environment_variables
    actions = @client.create_actions_object(commands: de_cmd, environment:)
    regions = [@compute_region]
    labels = @client.job_labels(
      action: :differential_expression, study: @study, study_file: @cluster_file, user: @user,
      params_object: de_params
    )
    machine_type = de_params.machine_type
    custom_vm = @client.create_virtual_machine_object(machine_type:, labels:)
    resources = @client.create_resources_object(regions:, vm: custom_vm)
    pipeline = @client.create_pipeline_object(actions:, environment:, resources:)
    pipeline_request = @client.create_run_pipeline_request_object(pipeline:, labels:)
    assert pipeline_request.is_a? Google::Apis::LifesciencesV2beta::RunPipelineRequest
    assert_equal pipeline, pipeline_request.pipeline
    assert_equal actions, pipeline_request.pipeline.actions
    assert_equal environment, pipeline_request.pipeline.environment
    assert_equal resources, pipeline_request.pipeline.resources
    assert_equal de_cmd, pipeline_request.pipeline.actions.commands
    assert_equal labels, custom_vm.labels
    assert_equal labels, pipeline_request.labels

    # specifically check machine type override
    assert_equal de_params.machine_type, pipeline_request.pipeline.resources.virtual_machine.machine_type
  end

  test 'should set labels for job' do
    labels = @client.job_labels(
      action: :ingest_cluster, study: @study, study_file: @cluster_file, user: @user, params_object: nil
    )
    ingest_tag = AdminConfiguration.get_ingest_docker_image_attributes[:tag].gsub(/\./, '_')
    expected_labels = {
      study_accession: @study.accession.downcase,
      user_id: @user.id.to_s,
      filename: 'cluster_txt',
      action: 'ingest_pipeline',
      docker_image: 'scp-ingest-pipeline',
      docker_tag: ingest_tag,
      environment: 'test',
      file_type: 'cluster',
      machine_type: LifeSciencesApiClient::DEFAULT_MACHINE_TYPE,
      boot_disk_size_gb: '300'
    }
    assert_equal expected_labels, labels
  end

  test 'should get correct label for action' do
    LifeSciencesApiClient::FILE_TYPES_BY_ACTION.keys.select { |k| k =~ /ingest/ }.each do |action|
      assert_equal 'ingest_pipeline', @client.label_for_action(action)
    end
    assert_equal 'differential_expression', @client.label_for_action('differential_expression')
    assert_equal 'data_cache_pipeline', @client.label_for_action('render_expression_arrays')
    assert_equal 'foo', @client.label_for_action('foo')
  end

  test 'should sanitize label' do
    assert_equal 'foo_bar', @client.sanitize_label('FOO&bar')
    assert_equal 'n1-highcpu-96', @client.sanitize_label('n1-highcpu-96')
    # test length truncation
    long_label = SecureRandom.alphanumeric(128)
    sanitized_label = @client.sanitize_label(long_label)
    assert_equal 63, sanitized_label.chars.size
    assert_equal long_label.downcase.truncate(63, omission: ''), sanitized_label
  end
end
