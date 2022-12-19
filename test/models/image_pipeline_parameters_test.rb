require 'test_helper'

class ImagePipelineParametersTest < ActiveSupport::TestCase
  before(:all) do
    @params = {
      accession: 'SCP1234',
      cluster: 'UMAP',
      bucket: 'test_bucket',
      environment: 'test',
      data_cache_perftime: 120_000
    }
    @pipeline_params = ImagePipelineParameters.new(@params)
  end

  test 'should instantiate and validate parameters' do
    assert @pipeline_params.valid?
    invalid = ImagePipelineParameters.new(environment: 'foo', machine_type: 'bar', docker_image: 'blah')
    assert_not invalid.valid?
    assert_equal %i[accession bucket cluster cores data_cache_perftime docker_image environment machine_type],
                 invalid.errors.attribute_names.sort

    # test overriding defaults
    fake_image = 'gcr.io/repository/image:0.1.2'
    new_params = ImagePipelineParameters.new(@params.merge(cores: 12, docker_image: fake_image))
    assert new_params.valid?
    assert_equal fake_image, new_params.docker_image
    assert_equal 12, new_params.cores
  end

  test 'should ensure core count does not exceed requested machine type' do
    assert @pipeline_params.cores.to_i < @pipeline_params.machine_type_cores.to_i
    bad_params = ImagePipelineParameters.new(@params.merge(cores: 128))
    assert_not bad_params.valid?
    assert_equal %i[cores], bad_params.errors.attribute_names
  end

  test 'should get cores from machine type' do
    assert_equal 95, @pipeline_params.cores
    assert_equal 96, @pipeline_params.machine_type_cores
    custom_machine_type = ImagePipelineParameters.new(@params.merge(machine_type: 'n1-standard-12'))
    assert_equal 11, custom_machine_type.cores
    assert_equal 12, custom_machine_type.machine_type_cores
    # this will fail to validate, but shows that a bad machine_type doesn't throw any other errors
    bad_machine = ImagePipelineParameters.new(@params.merge(machine_type: 'foo'))
    assert_equal(-1, bad_machine.cores)
    assert_equal 0, bad_machine.machine_type_cores
  end

  test 'should format image pipeline array parameters for cli' do
    options_array = @pipeline_params.to_options_array
    @pipeline_params.attributes.each do |name, value|
      expected_name = Parameterizable.to_cli_opt(name)
      assert_includes options_array, expected_name
      assert_includes options_array, value.to_s # gotcha as cores is converted to string for command line
    end
  end
end
