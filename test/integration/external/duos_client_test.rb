require 'test_helper'

class DuosClientTest < ActiveSupport::TestCase
  before(:all) do
    @random_seed = SecureRandom.uuid
    @user = FactoryBot.create(:user, test_array: @@users_to_clean)
    @study = FactoryBot.create(:detached_study,
                               name_prefix: "Duos Testing Study #{@random_seed}",
                               description: 'SCP testing study for DUOS registration',
                               public: true,
                               user: @user,
                               initialized: true,
                               test_array: @@studies_to_clean)
    # add top-level metadata for results
    annotation_input = [
      { name: 'donor_id', type: 'group', values: %w[donor_1 donor_2 donor_3 donor_4 donor_5] },
      { name: 'disease', type: 'group', values: Array.new(5, 'MONDO_0005109') },
      { name: 'disease__ontology_label', type: 'group', values: Array.new(5, 'HIV infectious disease') },
      { name: 'species', type: 'group', values: Array.new(5, 'NCBITaxon_9606') },
      { name: 'species__ontology_label', type: 'group', values: Array.new(5, 'Homo sapiens') },
      { name: 'library_preparation_protocol__ontology_label', type: 'group', values: Array.new(5, 'Seq-Well') },
      { name: 'organ__ontology_label', type: 'group', values: Array.new(5, 'milk') },
      { name: 'sex', type: 'group', values: Array.new(5, 'female') }
    ]
    FactoryBot.create(:metadata_file, name: 'metadata.txt', study: @study, use_metadata_convention: true,
                      cell_input: %w[cellA cellB cellC cellD cellE],
                      annotation_input: )
    @author = FactoryBot.create(:author, study: @study, corresponding: true)
    client = DuosClient.new
    @duos_available = client.api_available?
  end

  setup do
    @duos_client = DuosClient.new
  end

  teardown do
    @study.update(duos_dataset_id: nil)
    @study.reload
  end

  after(:all) do
    Author.delete_all
  end

  def skip_if_api_down
    unless @duos_available
      puts '-- skipping DUOS integration tests due to API being unavailable --'
      skip
    end
  end

  test 'should instantiate client' do
    client = DuosClient.new
    assert client.is_a?(DuosClient)
    assert client.api_root.start_with?('https://consent.dsde-')
  end

  test 'should get headers for request' do
    headers = @duos_client.headers_for_request
    assert headers['Authorization'] == "Bearer #{@duos_client.access_token['access_token']}"
    assert headers['Accept'] == 'application/json'
    assert headers['Content-Type'] == 'application/json'

    headers = @duos_client.headers_for_request(multipart: true)
    assert headers['Content-Type'] == 'multipart/form-data'
  end

  test 'should determine if request should be multipart' do
    assert_not @duos_client.is_multipart?(:get, nil)
    assert @duos_client.is_multipart?(:post, { foo: 'bar', file: 'data' })
    assert @duos_client.is_multipart?(:put, { foo: 'bar', file: 'data' })
  end

  test 'should confirm API is available' do
    skip_if_api_down
    assert @duos_client.api_available?
  end

  test 'should get registration info' do
    skip_if_api_down
    registration = @duos_client.registration
    assert registration.keys.include?('userId')
    assert registration.keys.include?('roles')
    assert_equal @duos_client.issuer, registration['email']
  end

  test 'should get user id' do
    skip_if_api_down
    assert @duos_client.user_id.is_a?(Integer)
  end

  test 'should get Sam diagnostic info' do
    skip_if_api_down
    diagnostics = @duos_client.sam_diagnostics
    assert_equal %w[adminEnabled enabled inAllUsersGroup inGoogleProxyGroup tosAccepted], diagnostics.keys.sort
  end

  test 'should confirm registration' do
    skip_if_api_down
    assert @duos_client.registered?
  end

  test 'should confirm terms of service are accepted' do
    skip_if_api_down
    assert @duos_client.tos_accepted?
  end

  test 'should format name for DUOS correctly' do
    formatted_name = @duos_client.duos_study_name(@study)
    expected_name = "#{@study.accession} - #{@study.name}"
    assert_equal expected_name, formatted_name
  end

  test 'should format description for DUOS correctly' do
    formatted_desc = @duos_client.duos_study_description(@study)
    expected_desc = "#{@study.description} #{DuosClient::PLATFORM_ID}"
    assert_equal expected_desc, formatted_desc
  end

  test 'should format schema for DUOS' do
    duos_data = @duos_client.schema_from(@study)
    assert duos_data.dig(:dataset, :studyName).start_with?(@study.accession)
    assert duos_data.dig(:dataset, :studyDescription).include?(DuosClient::PLATFORM_ID)
    assert_equal 'Homo sapiens', duos_data.dig(:dataset, :species)
    assert_equal 'HIV infectious disease', duos_data.dig(:dataset, :phenotypeIndication)
    assert_equal ['Seq-Well'], duos_data.dig(:dataset, :dataTypes)
    participant_count = duos_data.dig(:dataset, :consentGroups).first[:numberOfParticipants]
    assert_equal 5, participant_count
    assert_equal @author.email, duos_data.dig(:dataset, :dataCustodianEmail).first
  end

  test 'should load dataset JSON schema from DUOS' do
    schema = @client.dataset_schema
    assert schema['title'] == 'Dataset Registration Schema'
    assert schema['$schema'] == 'https://json-schema.org/draft/2019-09/schema'
    assert schema['version'].is_a?(Integer)
  end

  test 'should validate schema' do
    duos_data = @duos_client.schema_from(@study)
    assert @duos_client.validate_schema(duos_data).empty?
    assert @duos_client.validate_schema({ foo: 'bar' }).first['error'].present?
  end

  test 'should extract ids from dataset' do
    study_id = rand(1000..9999)
    dataset_id = rand(1000..9999)
    dataset = {
      studyName: @study.name,
      studyDescription: @study.description,
      studyId: study_id,
      consentGroups: [{ datasetId: dataset_id, consentGroupName: @study.name }]
    }
    ids = @duos_client.identifiers_from_dataset(dataset)
    assert_equal study_id, ids[:duos_study_id]
    assert_equal dataset_id, ids[:duos_dataset_id]
  end

  test 'should run full integration on study' do
    skip_if_api_down
    # create dataset
    dataset = @duos_client.create_dataset(@study)
    assert dataset.present?
    assert_equal @duos_client.duos_study_name(@study), dataset[:studyName]
    assert_equal @duos_client.duos_study_description(@study), dataset[:studyDescription]
    # load DUOS entities
    ids = @duos_client.identifiers_from_dataset(dataset)
    assert @duos_client.study(ids[:duos_study_id]).present?
    assert @duos_client.dataset(ids[:duos_dataset_id]).present?
    # update dataset, making sure to update study with new identifiers first
    @study.update(**ids)
    @study.update(public: false)
    @study.reload
    updated_dataset = @duos_client.update_dataset(@study)
    assert updated_dataset.present?
    updated_dataset[:publicVisibility]
    assert_not updated_dataset[:publicVisibility]
    # redact dataset
    assert @duos_client.redact_dataset
    assert_raises Faraday::ResourceNotFound do
      @duos_client.dataset(@study.duos_dataset_id)
      @duos_client.study(@study.duos_study_id)
    end
  end
end
