require 'test_helper'

class NemoClientTest < ActiveSupport::TestCase
  before(:all) do
    @username = ENV['NEMO_API_USERNAME']
    @password = ENV['NEMO_API_PASSWORD']
    @nemo_client = NemoClient.new
    @nemo_is_ok = @nemo_client.api_available?
    @skip_message = '-- skipping due to NeMO API being unavailable --'
    @identifiers = {
      collection: 'nemo:col-hwmwd2x',
      file: 'nemo:drc-jcvnj7k',
      grant: 'nemo:grn-gyy3k8j',
      project: 'nemo:std-5jvcwm1',
      sample: 'nemo:smp-xmd8d0y',
      subject: 'nemo:sbj-njhfvw6'
    }
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
    assert_equal @username, client.username
    assert_equal @password, client.password
  end

  test 'should check if NeMO is up' do
    skip_if_api_down
    assert @nemo_client.api_available?
  end

  test 'should format authentication header' do
    auth_header = @nemo_client.authorization_header
    username_password = auth_header[:Authorization].split.last # trim off 'Basic '
    assert_equal "#{@nemo_client.username}:#{@nemo_client.password}", Base64.decode64(username_password)
  end

  test 'should validate entity type' do
    assert_raises ArgumentError do
      @nemo_client.fetch_entity(:foo, 'bar')
    end
  end

  test 'should validate identifier format' do
    assert_raises ArgumentError do
      @nemo_client.file('foo')
    end
  end

  # TODO: SCP-5565 Check with NeMO re API, update and re-enable this test
  test 'should get an entity' do
    skip_if_api_down
    entity_type = @identifiers.keys.sample
    identifier = @identifiers[entity_type]
    entity = @nemo_client.fetch_entity(entity_type, identifier)
    assert entity.present?
  end

  test 'should get collection' do
    skip_if_api_down
    identifier = @identifiers[:collection]
    collection = @nemo_client.collection(identifier)
    assert collection.present?
    assert_equal 'human_variation_10X', collection['short_name']
  end

  # TODO: SCP-5565 Check with NeMO re API, update and re-enable this test
  test 'should get file' do
    skip_if_api_down
    identifier = @identifiers[:file]
    file = @nemo_client.file(identifier)
    assert file.present?
    filename = 'human_var_scVI_VLMC.h5ad'
    assert_equal filename, file['file_name']
    assert_equal 'h5ad', file['file_format']
    access_url = file['manifest_file_urls'].first['url']
    assert_equal filename, access_url.split('/').last
  end

  # TODO: SCP-5565 Check with NeMO re API, update and re-enable this test
  test 'should get grant' do
    skip_if_api_down
    identifier = @identifiers[:grant]
    grant = @nemo_client.grant(identifier)
    assert grant.present?
    assert_equal 'Allen Institute Funder', grant.dig('grant_info','grant_number')
    assert_equal 'Allen Institute Funder', grant['funding_agency']
  end

  test 'should get project' do
    skip_if_api_down
    identifier = @identifiers[:project]
    project = @nemo_client.project(identifier)
    assert project.present?
    assert_equal 'DNA methylation profiling of genomic DNA in individual mouse brain cell nuclei (RS1.1)',
                 project['title']
    assert_equal 'biccn', project['program']
    assert_equal 'ecker_sn_mCseq_proj', project['short_name']
  end

  # TODO: SCP-5565 Check with NeMO re API, update and re-enable this test
  # test 'should get publication' do
  #   skip_if_api_down
  #   identifier = @identifiers[:publication]
  #   publication = @nemo_client.publication(identifier)
  #   assert publication.present?
  #   assert_equal 'eLife', publication['journal']
  #   assert_equal 'https://doi.org/10.7554/eLife.64875', publication['doi']
  #   assert_equal ["human", "macaques", "house mouse"].sort, publication['taxonomies'].sort
  # end

  # TODO: SCP-5565 Check with NeMO re API, update and re-enable this test
  test 'should get sample' do
    skip_if_api_down
    identifier = @identifiers[:sample]
    sample = @nemo_client.sample(identifier)
    assert sample.present?
    assert_equal 'marm028_M1', sample['sample_name']
    assert sample['subjects'].any?
  end

  # TODO: SCP-5565 Check with NeMO re API, update and re-enable this test
  test 'should get subject' do
    skip_if_api_down
    identifier = @identifiers[:subject]
    subject = @nemo_client.subject(identifier)
    assert subject.present?
    assert_equal 'nonhuman-1U01MH114819', subject.dig('cohort_info', 'cohort_name')
    assert_equal 'A Molecular and cellular atlas of the marmoset brain', subject['grant_title']
    assert subject['samples'].any?
  end
end
