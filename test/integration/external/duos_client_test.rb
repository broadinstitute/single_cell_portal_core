require 'test_helper'

class DuosClientTest < ActiveSupport::TestCase
  before(:all) do
    @client = DuosClient.new
    @random_seed = SecureRandom.uuid
    @user = FactoryBot.create(:user, test_array: @@users_to_clean)
    @study = FactoryBot.create(:detached_study,
                               name_prefix: "Duos Testing Study #{@random_seed}",
                               description:'SCP testing study for DUOS registration',
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
    FactoryBot.create(:cluster_file, name: 'cluster_example.txt', study: @study)
  end

  test 'should instantiate client' do
    client = DuosClient.new
    assert client.is_a?(DuosClient)
    assert client.api_root.start_with?('https://consent.dsde-')
  end

  test 'should format name for DUOS correctly' do
    formatted_name = @client.duos_study_name(@study)
    expected_name = "#{@study.accession} #{@study.name}"
    assert_equal expected_name, formatted_name
  end

  test 'should format description for DUOS correctly' do
    formatted_desc = @client.duos_study_description(@study)
    expected_desc = "#{@study.description} #{DuosClient::PLATFORM_ID}"
    assert_equal expected_desc, formatted_desc
  end

  test 'should format schema for DUOS' do
    duos_data = @client.schema_from(@study)
    assert duos_data.dig(:dataset, :studyName).start_with?(@study.accession)
    assert duos_data.dig(:dataset, :studyDescription).include?(DuosClient::PLATFORM_ID)
  end
end
