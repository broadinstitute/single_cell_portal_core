# This file should contain all the record creation needed to seed the database with its default values.
# The data can then be loaded with the rake db:seed (or created alongside the db with db:setup).
#
# Examples:
#
#   cities = City.create([{ name: 'Chicago' }, { name: 'Copenhagen' }])
#   Mayor.create(name: 'Emanuel', city: cities.first)
#
@random_seed = File.open(Rails.root.join('.random_seed')).read.strip 
user = User.create!(email:'testing.user@gmail.com', password:'password', admin: true, uid: '12345',
                    api_access_token: {access_token: 'test-api-token', expires_in: 3600, expires_at: Time.zone.now + 1.hour})
user_2 = User.create!(email: 'sharing.user@gmail.com', password: 'password', uid: '67890')
# manually accept Terms of Service for sharing user to avoid breaking tests
TosAcceptance.create(email: user_2.email)
study = Study.create!(name: "Testing Study #{@random_seed}", description: '<p>This is the test study.</p>',
                      firecloud_project: ENV['PORTAL_NAMESPACE'], data_dir: 'test', user_id: user.id)
expression_file = StudyFile.create!(name: 'expression_matrix.txt', upload_file_name: 'expression_matrix.txt', study_id: study.id,
                                    file_type: 'Expression Matrix', y_axis_label: 'Expression Scores')
cluster_file = StudyFile.create!(name: 'Test Cluster', upload_file_name: 'coordinates.txt', study_id: study.id,
                                 file_type: 'Cluster', x_axis_label: 'X', y_axis_label: 'Y', z_axis_label: 'Z')
mm_coord_file = StudyFile.create!(name: 'GRCh38/test_matrix.mtx', upload: File.open(Rails.root.join('test', 'test_data', 'GRCh38', 'test_matrix.mtx')),
                                  file_type: 'MM Coordinate Matrix', study_id: study.id)
genes_file = StudyFile.create!(name: 'GRCh38/test_genes.tsv', upload: File.open(Rails.root.join('test', 'test_data', 'GRCh38', 'test_genes.tsv')),
                               file_type: '10X Genes File', study_id: study.id, options: {matrix_id: mm_coord_file.id.to_s})
barcodes = StudyFile.create!(name: 'GRCh38/barcodes.tsv', upload: File.open(Rails.root.join('test', 'test_data', 'GRCh38', 'barcodes.tsv')),
                               file_type: '10X Barcodes File', study_id: study.id, options: {matrix_id: mm_coord_file.id.to_s})
metadata_file = StudyFile.create!(name: 'metadata.txt', upload_file_name: 'metadata.txt', study_id: study.id,
                                  file_type: 'Metadata')
cluster = ClusterGroup.create!(name: 'Test Cluster', study_id: study.id, study_file_id: cluster_file.id, cluster_type: '3d', cell_annotations: [
    {
        name: 'Category',
        type: 'group',
        values: %w(a b c d)
    },
    {
        name: 'Intensity',
        type: 'numeric',
        values: []
    }
])
# create raw arrays of values to use in DataArrays and StudyMetadatum
category_array = ['a', 'b', 'c', 'd'].repeated_combination(18).to_a.flatten
metadata_label_array = ['E', 'F', 'G', 'H'].repeated_combination(18).to_a.flatten
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
cluster_cat_array = cluster.data_arrays.build(name: 'Category', cluster_name: cluster.name, array_type: 'annotations', array_index: 1,
                                    study_id: study.id, values: category_array, study_file_id: cluster_file.id)
cluster_cat_array.save!
cluster_int_array = cluster.data_arrays.build(name: 'Intensity', cluster_name: cluster.name, array_type: 'annotations', array_index: 1,
                                    study_id: study.id, values: intensity_array, study_file_id: cluster_file.id)
cluster_int_array.save!
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
                                      array_index: 1, study_id: study.id, study_file_id: expression_file.id, values: metadata_score_array)
gene1_vals.save!
gene1_cells = gene_1.data_arrays.build(name: gene_1.cell_key, array_type: 'cells', cluster_name: expression_file.name,
                                      array_index: 1, study_id: study.id, study_file_id: expression_file.id, values: all_cell_array)
gene1_cells.save!
gene2_vals = gene_2.data_arrays.build(name: gene_2.score_key, array_type: 'expression', cluster_name: expression_file.name,
                                      array_index: 1, study_id: study.id, study_file_id: expression_file.id, values: metadata_score_array)
gene2_vals.save!
gene2_cells = gene_2.data_arrays.build(name: gene_2.cell_key, array_type: 'cells', cluster_name: expression_file.name,
                                       array_index: 1, study_id: study.id, study_file_id: expression_file.id, values: all_cell_array)
gene2_cells.save!

# API TEST SEEDS
api_study = Study.create!(name: "API Test Study #{@random_seed}", data_dir: 'api_test_study', user_id: user.id,
                          firecloud_project: ENV['PORTAL_NAMESPACE'])
StudyShare.create!(email: 'fake.email@gmail.com', permission: 'Reviewer', study_id: api_study.id)
StudyFile.create!(name: 'cluster_example.txt', upload: File.open(Rails.root.join('test', 'test_data', 'cluster_example.txt')),
                  study_id: api_study.id, file_type: 'Cluster')
DirectoryListing.create!(name: 'csvs', file_type: 'csv', files: [{name: 'foo.csv', size: 100, generation: '12345'}],
                         sync_status: true, study_id: api_study.id)
StudyFileBundle.create!(bundle_type: 'BAM', original_file_list: [{'name' => 'sample_1.bam', 'file_type' => 'BAM'},
                                                                 {'name' => 'sample_1.bam.bai', 'file_type' => 'BAM Index'}],
                        study_id: api_study.id)
User.create!(email:'testing.user.2@gmail.com', password:'someotherpassword',
             api_access_token: {access_token: 'test-api-token-2', expires_in: 3600, expires_at: Time.zone.now + 1.hour})

# Analysis Configuration seeds
AnalysisConfiguration.create(namespace: 'single-cell-portal', name: 'split-cluster', snapshot: 1, user_id: user.id,
                             configuration_namespace: 'single-cell-portal', configuration_name: 'split-cluster',
                             configuration_snapshot: 2, description: 'This is a test description.')

# SearchFacet seeds
SearchFacet.create(name: 'Species', identifier: 'species', filters: [{id: 'NCBITaxon_9606', name: 'Homo sapiens'}],
                   ontology_urls: [{name: 'NCBI organismal classification', url: 'https://www.ebi.ac.uk/ols/api/ontologies/ncbitaxon'}],
                   is_ontology_based: true, is_array_based: false, big_query_id_column: 'species', big_query_name_column: 'species__ontology_label',
                   convention_name: 'alexandria_convention', convention_version: '1.1.3')
