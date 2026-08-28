require 'test_helper'

class ScviIngestParametersTest < ActiveSupport::TestCase
  before(:all) do
    @defaults = {
      gex_file: 'gs://test-bucket/gex.h5ad',
      atac_file: 'gs://test-bucket/atac.h5ad',
      ref_file: 'gs://test-bucket/ref.h5ad',
      accession: 'SCP1234'
    }
  end

  test 'should instantiate and validate params' do
    params = ScviIngestParameters.new(**@defaults)
    assert params.valid?
    assert_equal 'n1-highmem-8',  params.machine_type
    assert params.localize
    assert params.docker_image.include?('scvi-scanvi')

    invalid_params = ScviIngestParameters.new
    assert_not invalid_params.valid?
    @defaults.keys.each do |key|
      assert invalid_params.errors.key?(key)
    end
    invalid_params.machine_type = 'foo'
    assert_not invalid_params.valid?
    assert invalid_params.errors.key?(:machine_type)
  end
end
