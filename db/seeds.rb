# This file should contain all the record creation needed to seed the database with its default values.
# The data can then be loaded with the rake db:seed (or created alongside the db with db:setup).
#
# Examples:
#
#   cities = City.create([{ name: 'Chicago' }, { name: 'Copenhagen' }])
#   Mayor.create(name: 'Emanuel', city: cities.first)
#
File.open(Rails.root.join('.random_seed')) do |file|
  @random_seed = file.read.strip
end
user_access_token = {access_token: 'test-api-token', expires_in: 3600, expires_at: Time.zone.now + 1.hour}
user_2_access_token = {access_token: 'test-api-token-2', expires_in: 3600, expires_at: Time.zone.now + 1.hour}
user = User.find_or_initialize_by(email:'testing.user@gmail.com')
user.update!(password:'password', admin: true, uid: '12345', metrics_uuid: SecureRandom.uuid,
             api_access_token: user_access_token, access_token: user_access_token, registered_for_firecloud: true)
user_2 = User.find_or_initialize_by(email: 'sharing.user@gmail.com')
user_2.update!(password: 'password', uid: '67890',
               api_access_token: user_2_access_token, access_token: user_2_access_token, metrics_uuid: SecureRandom.uuid)

TosAcceptance.create(email: user.email)
TosAcceptance.create(email: user_2.email)
study = Study.create!(name: "Testing Study #{@random_seed}", firecloud_project: ENV['PORTAL_NAMESPACE'], user_id: user.id)
detail = study.build_study_detail
detail.update(full_description: "<p>This is the test study.</p>")
StudyShare.create!(email: 'my-user-group@firecloud.org', permission: 'Reviewer', study_id: study.id,
                   firecloud_project: study.firecloud_project, firecloud_workspace: study.firecloud_workspace)
example_files = {
    expression: {
        name: 'expression_matrix_example.txt',
        path: 'test/test_data/expression_matrix_example.txt',
        file_type: 'Expression Matrix',
        y_axis_label: 'Expression Scores',
        study_id: study.id
    },
    metadata: {
        name: 'metadata_example.txt',
        path: 'test/test_data/alexandria_convention/metadata.v2-0-0.txt',
        file_type: 'Metadata',
        use_metadata_convention: true,
        study_id: study.id
    },
    cluster: {
        name: 'cluster_example.txt',
        path: 'test/test_data/cluster_example.txt',
        file_type: 'Cluster',
        study_id: study.id,
        x_axis_label: 'X',
        y_axis_label: 'Y',
        z_axis_label: 'Z'
    }
}
example_files.values.each do |file_attributes|
  File.open(File.join(file_attributes[:path])) do |upload|
    file_attributes.delete(:path)
    file_attributes[:upload] = upload
    study_file = StudyFile.create!(file_attributes)
    study.send_to_firecloud(study_file)
  end
end
study.reload
expression_file = study.expression_matrix_files.first
cluster_file = study.cluster_ordinations_files.first
metadata_file = study.metadata_file
cluster = ClusterGroup.create!(name: 'Test Cluster', study_id: study.id, study_file_id: cluster_file.id, cluster_type: '3d',
                               cell_annotations: [
                                 {
                                   name: 'Category',
                                   type: 'group',
                                   values: %w(a b c d)
                                 },
                                 {
                                   name: 'Intensity',
                                   type: 'numeric',
                                   values: []
                                 }])
# create raw arrays of values to use in DataArrays and StudyMetadatum
category_array = %w[a b c d].repeated_combination(18).to_a.flatten
metadata_label_array = %w[E F G H].repeated_combination(18).to_a.flatten
point_array = 0.upto(category_array.size - 1).to_a
cluster_cell_array = point_array.map {|p| "cell_#{p}"}
all_cell_array = 0.upto(metadata_label_array.size - 1).map {|c| "cell_#{c}"}
intensity_array = point_array.map {|p| rand}
metadata_score_array = all_cell_array.map {|p| rand}
study_cells = study.data_arrays.build(name: 'All Cells', array_type: 'cells', cluster_name: 'Testing Study', array_index: 1,
                                      values: all_cell_array, study_id: study.id, study_file_id: expression_file.id)
study_cells.save!
x_array = cluster.data_arrays.build(name: 'x', cluster_name: cluster.name, array_type: 'coordinates', array_index: 1,
                                    study_id: study.id, values: point_array, study_file_id: cluster_file.id)
x_array.save!
y_array = cluster.data_arrays.build(name: 'y', cluster_name: cluster.name, array_type: 'coordinates', array_index: 1,
                                    study_id: study.id, values: point_array, study_file_id: cluster_file.id)
y_array.save!
z_array = cluster.data_arrays.build(name: 'z', cluster_name: cluster.name, array_type: 'coordinates', array_index: 1,
                                    study_id: study.id, values: point_array, study_file_id: cluster_file.id)
z_array.save!
cluster_txt = cluster.data_arrays.build(name: 'text', cluster_name: cluster.name, array_type: 'cells', array_index: 1,
                                        study_id: study.id, values: cluster_cell_array, study_file_id: cluster_file.id)
cluster_txt.save!
cluster_cat_array = cluster.data_arrays.build(name: 'Category', cluster_name: cluster.name, array_type: 'annotations',
                                              array_index: 1, study_id: study.id, values: category_array,
                                              study_file_id: cluster_file.id)
cluster_cat_array.save!
cluster_int_array = cluster.data_arrays.build(name: 'Intensity', cluster_name: cluster.name, array_type: 'annotations',
                                              array_index: 1, study_id: study.id, values: intensity_array,
                                              study_file_id: cluster_file.id)
cluster_int_array.save!
# set point count on cluster after arrays are saved
cluster.set_point_count!

cell_metadata_1 = CellMetadatum.create!(name: 'Label', annotation_type: 'group', study_id: study.id,
                                        values: metadata_label_array.uniq, study_file_id: metadata_file.id)
cell_metadata_2 = CellMetadatum.create!(name: 'Score', annotation_type: 'numeric', study_id: study.id,
                                        values: metadata_score_array.uniq, study_file_id: metadata_file.id)
meta1_vals = cell_metadata_1.data_arrays.build(name: 'Label', cluster_name: 'Label', array_type: 'annotations', array_index: 1,
                                               values: metadata_label_array, study_id: study.id, study_file_id: metadata_file.id)
meta1_vals.save!
meta2_vals = cell_metadata_2.data_arrays.build(name: 'Score', cluster_name: 'Score', array_type: 'annotations', array_index: 1,
                                               values: metadata_score_array, study_id: study.id, study_file_id: metadata_file.id)
meta2_vals.save!
gene_1 = Gene.create!(name: 'Gene_1', searchable_name: 'gene_1', study_id: study.id, study_file_id: expression_file.id)
gene_2 = Gene.create!(name: 'Gene_2', searchable_name: 'gene_2', study_id: study.id, study_file_id: expression_file.id)
gene1_vals = gene_1.data_arrays.build(name: gene_1.score_key, array_type: 'expression', cluster_name: expression_file.name,
                                      array_index: 1, study_id: study.id, study_file_id: expression_file.id,
                                      values: metadata_score_array)
gene1_vals.save!
gene1_cells = gene_1.data_arrays.build(name: gene_1.cell_key, array_type: 'cells', cluster_name: expression_file.name,
                                      array_index: 1, study_id: study.id, study_file_id: expression_file.id,
                                       values: all_cell_array)
gene1_cells.save!
gene2_vals = gene_2.data_arrays.build(name: gene_2.score_key, array_type: 'expression', cluster_name: expression_file.name,
                                      array_index: 1, study_id: study.id, study_file_id: expression_file.id,
                                      values: metadata_score_array)
gene2_vals.save!
gene2_cells = gene_2.data_arrays.build(name: gene_2.cell_key, array_type: 'cells', cluster_name: expression_file.name,
                                       array_index: 1, study_id: study.id, study_file_id: expression_file.id,
                                       values: all_cell_array)
gene2_cells.save!
DirectoryListing.create!(name: 'fastq', file_type: 'fastq',
                         files: [
                           { name: '1_L1_001.fastq', size: 100, generation: '12345' },
                           { name: '1_R1_001.fastq', size: 100, generation: '12345' },
                           { name: '2_L1_001.fastq', size: 100, generation: '12345' },
                           { name: '2_R1_001.fastq', size: 100, generation: '12345' },
                         ], sync_status: true, study_id: study.id)
# API TEST SEEDS
api_study = Study.create!(name: "API Test Study #{@random_seed}", data_dir: 'api_test_study', user_id: user.id,
                          firecloud_project: ENV['PORTAL_NAMESPACE'])
StudyShare.create!(email: 'fake.email@gmail.com', permission: 'Reviewer', study_id: api_study.id)
File.open(Rails.root.join('test', 'test_data', 'cluster_example.txt')) do |upload|
  api_cluster_file = StudyFile.create!(name: 'cluster_example.txt', upload: upload,
                                       study_id: api_study.id, file_type: 'Cluster')
  # push file to bucket for use in API download tests
  api_study.send_to_firecloud(api_cluster_file)
end
StudyFile.create(study_id: api_study.id, name: 'SRA Study for housing fastq data', description: 'SRA Study for housing fastq data',
                 file_type: 'Fastq', status: 'uploaded', human_fastq_url: 'https://www.ncbi.nlm.nih.gov/sra/ERX4159348[accn]')
DirectoryListing.create!(name: 'csvs', file_type: 'csv', files: [{name: 'foo.csv', size: 100, generation: '12345'}],
                         sync_status: true, study_id: api_study.id)
StudyFileBundle.create!(bundle_type: 'BAM',
                        original_file_list: [
                          { 'name' => 'sample_1.bam', 'file_type' => 'BAM' },
                          { 'name' => 'sample_1.bam.bai', 'file_type' => 'BAM Index' }],
                        study_id: api_study.id)
resource = api_study.external_resources.build(url: 'https://singlecell.broadinstitute.org', title: 'SCP',
                                              description: 'Link to Single Cell Portal')
resource.save!
api_user = User.create!(email:'testing.user.2@gmail.com', password:'someotherpassword', metrics_uuid: SecureRandom.uuid,
             api_access_token: { access_token: 'test-api-token-2', expires_in: 3600, expires_at: Time.zone.now + 1.hour })

# Analysis Configuration seeds
AnalysisConfiguration.create!(namespace: 'single-cell-portal', name: 'split-cluster', snapshot: 1, user_id: user.id,
                             configuration_namespace: 'single-cell-portal', configuration_name: 'split-cluster',
                             configuration_snapshot: 2, description: 'This is a test description.')

# SearchFacet seeds
# These facets represent 3 of the main types: String-based (both for array- and non-array columns), and numeric
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
                    data_type: 'string', is_ontology_based: true, is_array_based: false, big_query_id_column: 'species',
                    big_query_name_column: 'species__ontology_label', convention_name: 'Alexandria Metadata Convention',
                    convention_version: '2.2.0')
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

# Preset search seeds
PresetSearch.create!(name: 'Test Search', search_terms: ["Testing Study"],
                     facet_filters: ['species:NCBITaxon_9606', 'disease:MONDO_0000001'], accession_list: %w(SCP1))

# Feature flag seeds
FeatureFlag.create!(name: 'convention_required', default_value: false)
FeatureFlag.create!(name: 'raw_counts_required_backend', default_value: false)
