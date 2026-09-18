require 'test_helper'

class NemoClientTest < ActiveSupport::TestCase
  before(:all) do
    @nemo_client = NemoClient.new
    @nemo_is_ok = @nemo_client.api_available?
    @skip_message = '-- skipping due to NeMO API being unavailable --'
    @identifiers = {
      collection: 'nemo:col-hwmwd2x',
      file: 'nemo:fil-0njjzpd',
      grant: 'nemo:grn-gyy3k8j',
      project: 'nemo:std-5jvcwm1',
      sample: 'nemo:smp-xmd8d0y',
      subject: 'nemo:sbj-njhfvw6'
    }
  end

  # skip a test if Nemo API is not up ; prevents unnecessary build failures due to releases/maintenance
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
    entity_type = @identifiers.keys.reject {|k| k == :file }.sample
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

  test 'should get file' do
    skip_if_api_down
    identifier = @identifiers[:file]
    file = @nemo_client.file(identifier)
    assert file.present?
    filename = 'PYHINRVF_Pool27_Batch3_IVSAOxycodoneStudy1.h5ad'
    assert_equal filename, file['file_name']
    assert_equal 'h5ad', file['file_format']
    access_url = file['manifest_file_urls'].first['url']
    assert_equal filename, access_url.split('/').last
  end

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

  test 'should get sample' do
    skip_if_api_down
    identifier = @identifiers[:sample]
    sample = @nemo_client.sample(identifier)
    assert sample.present?
    assert_equal 'marm028_M1', sample['sample_name']
    assert sample['subjects'].any?
  end

  test 'should get subject' do
    skip_if_api_down
    identifier = @identifiers[:subject]
    subject = @nemo_client.subject(identifier)
    assert subject.present?
    assert_equal 'nonhuman-1U01MH114819', subject.dig('cohort_info', 'cohort_name')
    assert_equal 'A Molecular and cellular atlas of the marmoset brain', subject['grant_title']
    assert subject['samples'].any?
  end

  test 'shoud extract id from url' do
    url = 'https://assets.nemoarchive.org/api/collection/nemo:col-hwmwd2x'
    extracted_id = @nemo_client.entity_id_from_url(url)
    assert_equal 'nemo:col-hwmwd2x', extracted_id
    entity = { name: 'analysis.h5ad', url: 'https://assets.nemoarchive.org/api/file/nemo:fil-0njjzpd' }
    extracted_id = @nemo_client.entity_id_from_url(entity, attribute: 'url')
    assert_equal 'nemo:fil-0njjzpd', extracted_id
  end

  test 'should extract id from entity' do
    skip_if_api_down
    identifier = @identifiers[:file]
    file = @nemo_client.file(identifier)
    parent_file_id = @nemo_client.extract_associated_id(file, :parent_files)
    assert parent_file_id.present?
    assert_match /nemo:fil-[a-z0-9]{7}$/, parent_file_id
    analysis_name = @nemo_client.extract_associated_id(file, :analysis, attribute: :analysis_name)
    assert_equal 'Optimus_v8.0.4', analysis_name
  end

  test 'should extract multiple ids from entity' do
    skip_if_api_down
    identifier = @identifiers[:file]
    file = @nemo_client.file(identifier)
    parent_file_ids = @nemo_client.extract_associated_ids(file, :parent_files)
    assert parent_file_ids.present?
    assert parent_file_ids.is_a?(Array)
    assert parent_file_ids.all? {|id| id.match?(/nemo:fil-[a-z0-9]{7}$/) }
  end
end
