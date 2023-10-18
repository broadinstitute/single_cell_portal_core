require 'test_helper'

class NemoClientTest < ActiveSupport::TestCase
  before(:all) do
    @nemo_client = NemoClient.new
    @nemo_is_ok = @nemo_client.api_available?
    @skip_message = '-- skipping due to NeMO API being unavailable --'
  end

  # skip a test if Azul is not up ; prevents unnecessary build failures due to releases/maintenance
  def skip_if_api_down
    unless @nemo_is_ok
      puts @skip_message; skip
    end
  end

  test 'should instantiate client' do
    client = NemoClient.new
    assert_equal NemoClient::BASE_URL, client.api_root
  end

  test 'should check if NeMO is up' do
    skip_if_api_down
    assert @nemo_client.api_available?
  end
end
