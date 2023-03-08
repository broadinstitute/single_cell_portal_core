require 'test_helper'

class StudyFileBundleTest < ActiveSupport::TestCase

  before(:all) do
    @user = FactoryBot.create(:admin_user, test_array: @@users_to_clean)
    @study = FactoryBot.create(:detached_study,
                               name_prefix: 'StudyFileBundle Test',
                               user: @user,
                               test_array: @@studies_to_clean)
    @matrix = FactoryBot.create(:study_file,
                                name: 'matrix.mtx',
                                study: @study,
                                file_type: 'MM Coordinate Matrix',
                                parse_status: 'parsed',
                                status: 'uploaded',
                                expression_file_info: {
                                  is_raw_counts: false,
                                  library_preparation_protocol: 'Drop-seq',
                                  biosample_input_type: 'Whole cell',
                                  modality: 'Proteomic'
                                })
    @genes = FactoryBot.create(:study_file,
                               name: 'genes.txt',
                               study: @study,
                               status: 'uploaded',
                               file_type: '10X Genes File')
    @barcodes = FactoryBot.create(:study_file,
                                  name: 'barcodes.txt',
                                  study: @study,
                                  status: 'uploaded',
                                  file_type: '10X Barcodes File')

    @bundle = StudyFileBundle.new(study: @study, bundle_type: @matrix.file_type)
    @bundle.add_files(@matrix, @genes, @barcodes)
    @bundle.save!
    @cluster_file = FactoryBot.create(:cluster_file,
                                      name: 'cluster.txt',
                                      parse_status: 'parsed',
                                      status: 'uploaded',
                                      study: @study)
    @coordinate_file = FactoryBot.create(:study_file,
                                         study: @study,
                                         name: 'labels.txt',
                                         parse_status: 'parsed',
                                         status: 'uploaded',
                                         file_type: 'Coordinate Labels')
  end

  teardown do
    @cluster_file.update(status: 'uploaded')
    @study.study_file_bundles.where(bundle_type: 'Cluster').delete_all
  end

  test 'should find completed bundle' do
    assert @bundle.completed?
    assert @matrix.has_completed_bundle?
  end

  test 'should find parent and bundled files' do
    assert_equal @matrix.id, @bundle.parent.id
    assert_equal %w[genes.txt barcodes.txt], @bundle.bundled_files.pluck(:name)
    assert @matrix.is_bundle_parent?
  end

  test 'should determine that all files should bundle' do
    [@matrix, @genes, @barcodes].each do |study_file|
      assert study_file.should_bundle?
    end
    assert_not @cluster_file.should_bundle?
  end

  test 'should handle incomplete bundles safely until completed' do
    new_bundle = StudyFileBundle.new(study: @study, bundle_type: 'Cluster')
    assert_not new_bundle.completed?
    assert_nil new_bundle.parent
    new_bundle.add_files(@cluster_file)
    assert_not new_bundle.completed?
    assert_equal @cluster_file.id, new_bundle.parent.id
    assert_empty new_bundle.bundled_files.to_a
    new_bundle.add_files(@coordinate_file)
    assert new_bundle.completed?
    assert_equal [@coordinate_file], new_bundle.bundled_files.to_a
  end

  test 'should check upload status for completion' do
    @cluster_file.update(status: 'new')
    incomplete_bundle = StudyFileBundle.new(study: @study, bundle_type: 'Cluster')
    incomplete_bundle.add_files(@cluster_file, @coordinate_file)
    assert_not incomplete_bundle.completed?
  end

  test 'should find bundled files by type' do
    [@genes, @barcodes].each do |bundled_file|
      assert_equal bundled_file, @bundle.bundled_file_by_type(bundled_file.file_type)
    end
  end

  test 'should get file types' do
    expected = [@matrix, @genes, @barcodes].map(&:file_type).sort
    assert_equal expected, @bundle.original_file_types.sort
    assert_equal expected, @bundle.file_types.sort
  end

  test 'should generate file list' do
    files = [@matrix, @genes, @barcodes]
    expected = files.map { |file| { name: file.name, file_type: file.file_type }.with_indifferent_access }
    assert_equal expected, StudyFileBundle.generate_file_list(*files)
  end
end
