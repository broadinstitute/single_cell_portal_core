# test_data_populator.rb
#
# creates model instances as needed for tests without having to use seeds.rb
# can add example files to an already existing study in the test environment.  this differs from FactoryBot in that it is
# intended for regular, non-detached studies as it will push physical files to workspace buckets.  this also differs
# from SyntheticStudyPopulator in that it does not parse files
# can also create the 3 default SearchFacet instances for species, disease, and organism_age commonly used in tests
class TestDataPopulator

  # normal example test files
  EXAMPLE_FILES = {
    expression: {
      name: 'expression_matrix_example.txt',
      path: 'test/test_data/expression_matrix_example.txt',
      file_type: 'Expression Matrix'
    },
    metadata: {
      name: 'metadata_example.txt',
      path: 'test/test_data/alexandria_convention/metadata.v2-0-0.txt',
      file_type: 'Metadata',
      use_metadata_convention: true
    },
    cluster: {
      name: 'cluster_example.txt',
      path: 'test/test_data/cluster_example.txt',
      file_type: 'Cluster'
    }
  }.with_indifferent_access.freeze

  FILE_TYPES = EXAMPLE_FILES.keys.freeze

  # add example files to an existing, non-detached study and push to workspace bucket
  def self.add_files_to_study(study, file_types: FILE_TYPES)
    raise ArgumentError, "#{study.accession} cannot be used as it is detached" if study.detached?

    puts "Invoking TestDataPopulator on #{study.accession}"
    # select requested files/types, then create entries and push to workspace bucket
    EXAMPLE_FILES.select { |file_type, _| file_types.include? file_type }.values.each do |file_attributes|
      File.open(Rails.root.join(file_attributes[:path])) do |upload|
        attributes = file_attributes.deep_dup # make copy so downstream calls don't get nil/String TypeError
        attributes.delete(:path)
        attributes[:upload] = upload
        attributes[:study_id] = study.id
        print "Adding #{attributes[:name]} to #{study.accession}... "
        study_file = StudyFile.create!(attributes)
        puts "done, pushing file to bucket #{study.bucket_id}"
        StorageService.upload_study_file(study.storage_provider, study, study_file)
      end
    end
    study.reload # refresh study state on return
  end

  # clears out any existing search facets and re-creates defaults of species, disease, and organism_age
  def self.create_sample_search_facets
    SearchFacet.destroy_all
    SearchFacet.create!(name: 'Species', identifier: 'species',
                        filters: [
                          { id: 'NCBITaxon_9606', name: 'Homo sapiens' }
                        ],
                        public_filters: [
                          { id: 'NCBITaxon_9606', name: 'Homo sapiens' }
                        ],
                        ontology_urls: [
                          {
                            name: 'NCBI organismal classification',
                            url: 'https://www.ebi.ac.uk/ols/api/ontologies/ncbitaxon',
                            browser_url: nil
                          }
                        ],
                        data_type: 'string', is_ontology_based: true, is_array_based: false,
                        big_query_id_column: 'species', big_query_name_column: 'species__ontology_label',
                        convention_name: 'Alexandria Metadata Convention', convention_version: '2.2.0')
    SearchFacet.create!(name: 'Disease', identifier: 'disease',
                        filters: [
                          { id: 'MONDO_0000001', name: 'disease or disorder' }
                        ],
                        public_filters: [
                          { id: 'MONDO_0000001', name: 'disease or disorder' }
                        ],
                        ontology_urls: [
                          {
                            name: 'Monarch Disease Ontology',
                            url: 'https://www.ebi.ac.uk/ols/api/ontologies/mondo',
                            browser_url: nil
                          }, {
                            name: 'Phenotype And Trait Ontology',
                            url: 'https://www.ebi.ac.uk/ols/ontologies/pato',
                            browser_url: nil
                          }
                        ],
                        data_type: 'string', is_ontology_based: true, is_array_based: true, big_query_id_column: 'disease',
                        big_query_name_column: 'disease__ontology_label', convention_name: 'Alexandria Metadata Convention',
                        convention_version: '2.2.0')
    SearchFacet.create!(name: 'Organism Age', identifier: 'organism_age', big_query_id_column: 'organism_age',
                        big_query_name_column: 'organism_age', big_query_conversion_column: 'organism_age__seconds',
                        is_ontology_based: false, data_type: 'number', is_array_based: false,
                        convention_name: 'Alexandria Metadata Convention', convention_version: '2.2.0', unit: 'years')
  end
end
