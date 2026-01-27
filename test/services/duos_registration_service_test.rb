require 'test_helper'

class DuosRegistrationServiceTest < ActiveSupport::TestCase
  before(:all) do
    @random_seed = SecureRandom.uuid
    @user = FactoryBot.create(:user, test_array: @@users_to_clean)
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
    @accessions = []
    1.upto(3) do |i|
      study = FactoryBot.create(:detached_study,
                                name_prefix: "DuosRegistrationService Test Study no. #{i} #{@random_seed}",
                                description: "SCP testing study no. #{i} for DuosRegistrationService",
                                public: true,
                                user: @user,
                                initialized: true,
                                test_array: @@studies_to_clean)
      FactoryBot.create(:metadata_file, name: 'metadata.txt', study:, use_metadata_convention: true,
                        cell_input: %w[cellA cellB cellC cellD cellE],
                        annotation_input: )
      FactoryBot.create(:author, study:, corresponding: true)
      @accessions << study.accession
    end
  end

  after(:all) do
    Author.delete_all
  end

  test 'should load client' do
    client = DuosRegistrationService.client
    assert client.is_a?(DuosClient)
  end

  test 'should identify eligible studies for DUOS registration' do
    eligible_accessions = DuosRegistrationService.eligible_studies
    expected_accessions = Study.where(duos_dataset_id: nil, duos_study_id: nil).pluck(:accession)
    assert_equal expected_accessions.size, eligible_accessions.size
    assert_equal expected_accessions.sort, eligible_accessions.sort
    eligible_accessions.each do |accession|
      study = Study.find_by(accession:)
      assert DuosRegistrationService.study_eligible?(study)
    end
  end

  test 'should load required metadata for study' do
    accession = @accessions.sample
    study = Study.find_by(accession:)
    required = DuosRegistrationService.required_metadata(study)
    assert required[:diseases] == ['HIV infectious disease']
    assert required[:species] == ['Homo sapiens']
    assert required[:donor_count] == 5
    assert required[:data_types] == %w[Seq-Well]
  end

  test 'should register dataset in DUOS' do
    accession = @accessions.sample
    study = Study.find_by(accession:)
    dataset = DuosRegistrationService.client.schema_from(study)
    mock = Minitest::Mock.new
    mock.expect :create_dataset, dataset, [study]
    mock.expect :identifiers_from_dataset,
                { duos_dataset_id: 1234, duos_study_id: 5678 },
                [dataset]
    DuosRegistrationService.stub :client, mock do
      registration = DuosRegistrationService.register_dataset(study)
      assert registration.is_a?(Hash)
      study.reload
      assert_equal 1234, study.duos_dataset_id
      assert_equal 5678, study.duos_study_id
      mock.verify
    end
  end

  test 'should redact study from DUOS' do
    accession = @accessions.sample
    study = Study.find_by(accession:)
    study.update(duos_dataset_id: 1234, duos_study_id: 5678)
    mock = Minitest::Mock.new
    mock.expect :redact_dataset, true, [study]
    DuosRegistrationService.stub :client, mock do
      assert DuosRegistrationService.redact_dataset(study)
      study.reload
      assert_nil study.duos_dataset_id
      assert_nil study.duos_study_id
      mock.verify
    end
  end
end
