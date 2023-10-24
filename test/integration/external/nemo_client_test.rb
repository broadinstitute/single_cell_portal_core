require 'test_helper'

class NemoClientTest < ActiveSupport::TestCase
  before(:all) do
    @username = ENV['NEMO_API_USERNAME']
    @password = ENV['NEMO_API_PASSWORD']
    @nemo_client = NemoClient.new(username: @username, password: @password)
    @nemo_is_ok = @nemo_client.api_available?
    @skip_message = '-- skipping due to NeMO API being unavailable --'
    @file_id = 'c6c0fcfa-52d9-45ff-82b5-0864951878ce'
    @study_full_name = "Lein;Vlmc;Transcriptome;10X Chromium 3' V3 Sequencing"
  end

  # skip a test if Azul is not up ; prevents unnecessary build failures due to releases/maintenance
  def skip_if_api_down
    unless @nemo_is_ok
      puts @skip_message; skip
    end
  end

  test 'should instantiate client' do
    client = NemoClient.new(username: @username, password: @password)
    assert_equal NemoClient::BASE_URL, client.api_root
    assert_equal @username, client.username
    assert_equal @password, client.password
  end

  test 'should check if NeMO is up' do
    skip_if_api_down
    assert @nemo_client.api_available?
  end

  test 'should get a file' do
    file = @nemo_client.file(@file_id)&.dig('data')
    assert file.present?
    expected_keys = %w[subject sample file]
    assert_equal expected_keys.sort, file.keys.sort
    assert_equal @file_id, file.dig('file', 'file_id')
    assert_equal @study_full_name, file.dig('sample', 'study_full_name')
    %w[identifier md5 access size].each do |expected_attribute|
      assert_includes file['file'].keys, expected_attribute
    end
  end

  test 'should get a sample' do
    sample = @nemo_client.sample(@study_full_name)&.dig('data')
    assert sample.present?
    expected_keys = %w[case_id files sample subject]
    assert_equal expected_keys.sort, sample.keys.sort
    assert_equal @study_full_name, sample.dig('sample', 'study_full_name')
    assert_equal @file_id, sample['files'].first['file_id']
  end
end
