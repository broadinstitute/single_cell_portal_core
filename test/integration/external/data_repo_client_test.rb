require 'test_helper'

class DataRepoClientTest < ActiveSupport::TestCase

  before(:all) do
    @data_repo_client = ApplicationController.data_repo_client
    @dataset_id = '5813840c-46e4-47ab-89fe-d4da28834698' # dataset for snapshot, we don't actually have access to this
    @snapshot_id = '25740be5-b493-4185-84b0-bebf425c5072' # dev PulmonaryFibrosisGSE135893 snapshot
    @file_id = '1c36ad71-755d-4623-8a5c-c336ecf80073' # ID of loom file in PulmonaryFibrosisGSE135893 snapshot
    @filename = 'pulmonary-fibrosis-human-lung-10XV2.loom' # name of above file
    @drs_file_id = "drs://#{DataRepoClient::REPOSITORY_HOSTNAME}/v1_#{@snapshot_id}_#{@file_id}" # computed DRS id
    bucket_id = 'datarepo-dev-54946186-bucket'
    project_name = 'datarepo-dev-0f9f0d44'
    @gs_url = "gs://#{bucket_id}/#{@dataset_id}/#{@file_id}/#{@filename}" # computed GS url
    @https_url = "https://www.googleapis.com/storage/v1/b/#{bucket_id}/o/" \
                 "#{@dataset_id}%2F#{@file_id}%2F#{@filename}?userProject=#{project_name}&alt=media"
  end

  # skip a test if the TDR API is not up (since it is their dev instance there is no uptime guarantee)
  def skip_if_api_down
    unless @data_repo_client.api_available?
      puts '-- skipping due to TDR API being unavailable --' ; skip
    end
  end

  test 'should instantiate client' do
    client = DataRepoClient.new
    assert client.present?
    assert_equal Rails.application.config.tdr_api_base_url, client.api_root
  end

  test 'should refresh access token' do
    token = @data_repo_client.access_token
    current_expiry = @data_repo_client.expires_at
    sleep 1
    new_token = @data_repo_client.refresh_access_token!
    assert_not_equal token['access_token'], new_token['access_token']
    assert current_expiry < @data_repo_client.expires_at
  end

  test 'should get token expiration' do
    refute @data_repo_client.access_token_expired?
    @data_repo_client.expires_at = 1.day.ago
    assert @data_repo_client.access_token_expired?
  end

  test 'should get valid access token' do
    @data_repo_client.refresh_access_token!
    token = @data_repo_client.access_token
    current_expiry = @data_repo_client.expires_at
    valid_token = @data_repo_client.valid_access_token
    assert_equal token['access_token'], valid_token['access_token']
    @data_repo_client.expires_at = 1.day.ago
    sleep 1
    new_token = @data_repo_client.valid_access_token
    assert_not_equal token['access_token'], new_token['access_token']
    assert current_expiry < @data_repo_client.expires_at
  end

  test 'should get issuer email' do
    service_account_email = JSON.parse(File.open(@data_repo_client.service_account_credentials).read)['client_email']
    assert_equal service_account_email, @data_repo_client.issuer
  end

  test 'should determine ok response code' do
    200.upto(206) do |code|
      # only 203 & 205 should not return OK
      if code.even? || code == 201
        assert @data_repo_client.ok?(code)
      else
        refute @data_repo_client.ok?(code)
      end
    end
    refute @data_repo_client.ok?(404)
  end

  test 'should determine retry from response code' do
    [nil, 502, 503, 504].each do |code|
      assert @data_repo_client.should_retry?(code)
    end
    refute @data_repo_client.should_retry?(404)
  end

  test 'should merge query string params from hash' do
    opts = { foo: 'bar', bing: 'baz' }
    expected_query = '?foo=bar&bing=baz'
    assert_equal expected_query, @data_repo_client.merge_query_options(opts)
    # ensure params are uri-encoded
    new_opts = { one: 'foo', two: 'bar bing' }
    expected_encoded_query = '?one=foo&two=bar+bing'
    assert_equal expected_encoded_query, @data_repo_client.merge_query_options(new_opts)
  end

  test 'should parse response body' do
    response = {
      total: 1,
      items: [
        {
          id: SecureRandom.uuid, name: 'My Dataset', description: 'This is the description',
          createdDate: Time.zone.now.to_s(:db), profileId: SecureRandom.uuid
        }
      ]
    }.with_indifferent_access
    parsed_response = @data_repo_client.parse_response_body(response.to_json)
    assert_equal response, parsed_response.with_indifferent_access

    string_response = 'This is the response'
    parsed_string = @data_repo_client.parse_response_body(string_response)
    assert_equal string_response, parsed_string
  end

  test 'should get api status' do
    skip_if_api_down
    status = @data_repo_client.api_status
    assert status['ok']
  end

  test 'should check if api is available' do
    skip_if_api_down
    assert @data_repo_client.api_available?
  end

  test 'should get datasets' do
    skip_if_api_down
    datasets = @data_repo_client.get_datasets
    assert datasets['total'].present?
    skip 'got empty response for datasets' if datasets['items'].empty?
    dataset_id = datasets['items'].first['id']
    dataset = @data_repo_client.get_dataset(dataset_id)
    assert dataset.present?
  end

  test 'should get snapshots' do
    skip_if_api_down
    snapshots = @data_repo_client.get_snapshots
    assert snapshots['total'].present?
    skip 'got empty response for snapshots' if snapshots['items'].empty?
    snapshot_id = snapshots['items'].first['id']
    snapshot = @data_repo_client.get_snapshot(snapshot_id)
    assert snapshot.present?
  end

  test 'should get snapshot' do
    skip_if_api_down
    snapshot = @data_repo_client.get_snapshot(@snapshot_id)
    assert snapshot.present?
    # look for subset of keys to prevent test breaking if response structure changes
    expected_keys = %w[id name description createdDate source].sort
    assert_equal expected_keys, expected_keys & snapshot.keys
  end

  test 'should get file in snapshot' do
    skip_if_api_down
    file_info = @data_repo_client.get_snapshot_file_info(@snapshot_id, @file_id)
    assert file_info.present?
    assert_equal @file_id, file_info['fileId']
    assert file_info['size'] > 0, 'did not get a valid file size'
    found_gs_url = file_info.dig('fileDetail', 'accessUrl')
    assert_equal @gs_url, found_gs_url
  end

  test 'should generate query JSON from facets' do
    selected_facets = [
      { id: :species, filters: [{ id: 'NCBITaxon9609', name: 'Homo sapiens' }] },
      { id: :disease, filters: [
          { id: 'MONDO_0018076', name: 'tuberculosis' }, { id: 'MONDO_0005109', name: 'HIV infectious disease' }
        ]
      }
    ]
    species_field = FacetNameConverter.convert_schema_column(:alexandria, :tim, :species)
    disease_field = FacetNameConverter.convert_schema_column(:alexandria, :tim, :disease)
    expected_query = "([#{species_field}]:\"NCBITaxon9609\") OR ([#{species_field}]:\"Homo sapiens\") AND " \
                     "([#{disease_field}]:\"MONDO_0018076\") OR ([#{disease_field}]:\"tuberculosis\") OR " \
                     "([#{disease_field}]:\"MONDO_0005109\") OR ([#{disease_field}]:\"HIV infectious disease\")"

    query_json = @data_repo_client.generate_query_from_facets(selected_facets)
    assert_equal expected_query, query_json.dig(:query_string, :query)
  end

  test 'should generate query JSON from keywords' do
    keywords = %w[pulmonary human lung]
    name_field = FacetNameConverter.convert_schema_column(:alexandria, :tim, :study_name)
    description_field = FacetNameConverter.convert_schema_column(:alexandria, :tim, :study_description)
    expected_query = "([#{name_field}]:\"pulmonary\" OR [#{name_field}]:\"human\" OR [#{name_field}]:\"lung\") OR " \
                     "([#{description_field}]:\"pulmonary\" OR [#{description_field}]:\"human\" OR " \
                     "[#{description_field}]:\"lung\")"
    query_json = @data_repo_client.generate_query_from_keywords(keywords)
    assert_equal expected_query, query_json.dig(:query_string, :query)
  end

  test 'should generate query JSON from HCA project IDs' do
    project_id = '2c1a9a93d-d9de-4e65-9619-a9cec1052eaa'
    project_ids = [project_id]
    query_json = @data_repo_client.generate_query_for_projects(project_ids)
    expected_query = "(project_id: #{project_id})"
    assert_equal expected_query, query_json.dig(:query_string, :query)
  end

  test 'should merge query JSON for facets and keywords' do
    name_field = FacetNameConverter.convert_schema_column(:alexandria, :tim, :study_name)
    description_field = FacetNameConverter.convert_schema_column(:alexandria, :tim, :study_description)
    species_field = FacetNameConverter.convert_schema_column(:alexandria, :tim, :species)
    disease_field = FacetNameConverter.convert_schema_column(:alexandria, :tim, :disease)
    selected_facets = [
      { id: :species, filters: [{ id: 'NCBITaxon9609', name: 'Homo sapiens' }] },
      { id: :disease, filters: [
          { id: 'MONDO_0018076', name: 'tuberculosis' }, { id: 'MONDO_0005109', name: 'HIV infectious disease' }
        ]
      }
    ]
    keywords = %w[pulmonary human lung]
    expected_query = "(([#{species_field}]:\"NCBITaxon9609\") OR ([#{species_field}]:\"Homo sapiens\") AND " \
                     "([#{disease_field}]:\"MONDO_0018076\") OR ([#{disease_field}]:\"tuberculosis\") OR (" \
                     "[#{disease_field}]:\"MONDO_0005109\") OR ([#{disease_field}]:\"HIV infectious disease\")) AND " \
                     "(([#{name_field}]:\"pulmonary\" OR [#{name_field}]:\"human\" OR [#{name_field}]:\"lung\") OR " \
                     "([#{description_field}]:\"pulmonary\" OR [#{description_field}]:\"human\" OR " \
                     "[#{description_field}]:\"lung\"))"
    merged_query = @data_repo_client.merge_query_json(
      facet_query: @data_repo_client.generate_query_from_facets(selected_facets),
      term_query: @data_repo_client.generate_query_from_keywords(keywords)
    )
    assert_equal expected_query, merged_query.dig(:query_string, :query)
  end

  test 'should query snapshot index' do
    skip_if_api_down
    hca_project_id = 'c1a9a93d-d9de-4e65-9619-a9cec1052eaa'
    selected_facets = [
      { id: :species, filters: [{ id: 'NCBITaxon9609', name: 'Homo sapiens' }] },
      { id: :project_id, filters: [{ name: hca_project_id, id: hca_project_id }] }
    ]
    query_json = @data_repo_client.generate_query_from_facets(selected_facets)
    results = @data_repo_client.query_snapshot_indexes(query_json, snapshot_ids: [@snapshot_id])
    original_count = results['result'].count
    assert original_count > 0
    sample_row = results['result'].sample
    species_field_name = FacetNameConverter.convert_schema_column(:alexandria, :tim, :species)
    assert_equal 'Homo sapiens', sample_row[species_field_name]
    expected_project = 'Single-cell RNA-sequencing reveals profibrotic roles of distinct epithelial and mesenchymal ' \
                       'lineages in pulmonary fibrosis'
    project_title_field = FacetNameConverter.convert_schema_column(:alexandria, :tim, :study_name)
    assert_equal expected_project, sample_row[project_title_field]

    # refine query and re-run
    selected_facets << { id: :organism_age, filters: { min: 46, max: 72, unit: 'years' } }
    query_json = @data_repo_client.generate_query_from_facets(selected_facets)
    results = @data_repo_client.query_snapshot_indexes(query_json, snapshot_ids: [@snapshot_id])
    new_count = results['result'].count
    assert new_count < original_count
    sample_row = results['result'].sample
    assert_equal '46-72', sample_row['organism_age']
  end

  test 'should get file info from drs id' do
    skip_if_api_down
    file_info = @data_repo_client.get_drs_file_info(@drs_file_id)
    assert file_info.present?
    expected_id = @drs_file_id.split('/').last
    assert_equal expected_id, file_info['id']
    assert file_info['size'] > 0, 'did not get a valid file size'
    found_filename = file_info['name']
    assert_equal @filename, found_filename

    # ensure error handling
    assert_raise ArgumentError do
      @data_repo_client.get_drs_file_info('foo')
    end
  end

  test 'should get access url from drs id' do
    skip_if_api_down
    found_gs_url = @data_repo_client.get_access_url_from_drs_id(@drs_file_id, :gs)
    assert_equal @gs_url, found_gs_url

    found_https_url = @data_repo_client.get_access_url_from_drs_id(@drs_file_id, :https)
    assert_equal @https_url, found_https_url

    # ensure error handling
    assert_raise ArgumentError do
      @data_repo_client.get_access_url_from_drs_id('foo', :gs)
    end
  end
end
