require 'test_helper'

class NemoClientTest < ActiveSupport::TestCase
  before(:all) do
    @username = ENV['NEMO_API_USERNAME']
    @password = ENV['NEMO_API_PASSWORD']
    @nemo_client = NemoClient.new(username: @username, password: @password)
    @nemo_is_ok = @nemo_client.api_available?
    @skip_message = '-- skipping due to NeMO API being unavailable --'
    @identifiers = {
      collection: 'nemo:col-pxwhesp',
      file: 'nemo:der-ah1o5qb',
      grant: 'nemo:grn-qwzp05p',
      project: 'nemo:std-hoxfi7n',
      publication: 'nemo:dat-tfmg0va',
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
    client = NemoClient.new(username: @username, password: @password)
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
    assert_equal 'adey_sciATAC_human_cortex', collection['short_name']
  end

  test 'should get file' do
    skip_if_api_down
    identifier = @identifiers[:file]
    file = @nemo_client.file(identifier)
    assert file.present?
    filename = 'human_var_scVI_VLMC.h5ad.tar'
    assert_equal filename, file['file_name']
    assert_equal 'h5ad', file['file_format']
    access_url = file['urls'].first['url']
    assert_equal filename, access_url.split('/').last
  end

  test 'should get grant' do
    skip_if_api_down
    identifier = @identifiers[:grant]
    grant = @nemo_client.grant(identifier)
    assert grant.present?
    assert_equal '1U01MH114825-01', grant['grant_number']
    assert_equal 'NIMH', grant['funding_agency']
  end

  test 'should get project' do
    skip_if_api_down
    identifier = @identifiers[:project]
    project = @nemo_client.project(identifier)
    assert project.present?
    assert_equal 'study', project['project_type']
    assert_equal 'biccn', project['program']
    assert_equal 'dulac_poa_dev_sn_10x_proj', project['short_name']
  end

  test 'should get publication' do
    skip_if_api_down
    identifier = @identifiers[:publication]
    publication = @nemo_client.publication(identifier)
    assert publication.present?
    assert_equal 'Bakken_2021_dLGN_CrossSpecies_Rseq', publication['short_name']
    assert_equal 'https://doi.org/10.7554/eLife.64875', publication['doi']
    assert_equal ["human", "macaques", "house mouse"].sort, publication['taxonomies'].sort
  end

  test 'should get sample' do
    skip_if_api_down
    identifier = @identifiers[:sample]
    sample = @nemo_client.sample(identifier)
    assert sample.present?
    assert_equal 'marm028_M1', sample['source_sample_id']
    assert sample['files'].any?
  end

  test 'should get subject' do
    skip_if_api_down
    identifier = @identifiers[:subject]
    subject = @nemo_client.subject(identifier)
    assert subject.present?
    assert_equal 'CEMBA180911_4H', subject['source_subject_id']
    assert_equal 'DNA methylation profiling of genomic DNA in individual mouse brain cell nuclei (RS1.1)',
                 subject['grant_title']
  end
end