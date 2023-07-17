require 'test_helper'
require 'includes_helper'

class SyntheticStudyPopulatorTest < ActionDispatch::IntegrationTest

  SYNTH_STUDY_INFO = {
    name: 'Male Mouse brain',
    folder: 'mouse_brain'
  }.freeze

  before(:all) do
    @user = FactoryBot.create(:admin_user, test_array: @@users_to_clean)
    @taxon = Taxon.find_or_create_by!(common_name: 'mouse',
                                      scientific_name: 'Mus musculus',
                                      user: @user,
                                      ncbi_taxid: 10090,
                                      notes: 'fake mouse taxon for testing')
    @genome_assembly = GenomeAssembly.find_or_create_by!(name: 'GRCm38',
                                                         alias: nil,
                                                         release_date: '2012-01-09',
                                                         accession: "GCA_000001635.2",
                                                         taxon: @taxon)
    @genome_annotation = GenomeAnnotation.find_or_create_by!(name: 'Ensembl 94',
                                                             link: 'http://google.com/search?q=mouse',
                                                             index_link: 'http://google.com/search?q=mouse_index',
                                                             release_date: '2020-10-19',
                                                             genome_assembly: @genome_assembly)
  end

  after(:all) do
    # this will also destroy the dependent annotation and assembly
    Taxon.destroy_all
    study = Study.find_by(name: SYNTH_STUDY_INFO[:name])
    if study.present?
      study.destroy_and_remove_workspace
    end
  end

  # this test covers both convention data and raw/processed expression matrix files
  # validates that repeated cells are permitted across matrix files
  test 'should be able to populate a study with convention metadata' do
    skip 'test fails for unexplained reasons in CI only (see SCP-4189)'
    # SyntheticStudyPopulator does have logic for deleting existing sutdies on populate
    # but this is for belt-and-suspenders to make sure the delete is successful
    Study.find_by(name: SYNTH_STUDY_INFO[:name])&.destroy_and_remove_workspace

    assert_nil Study.find_by(name: SYNTH_STUDY_INFO[:name])
    @study = SyntheticStudyPopulator.populate(SYNTH_STUDY_INFO[:folder])
    populated_study = Study.find_by(name: SYNTH_STUDY_INFO[:name])

    assert_not_nil populated_study
    assert_equal 9, populated_study.study_files.count
    assert_equal 'Metadata', populated_study.study_files.first.file_type
    assert_not_nil populated_study.study_detail.full_description

    # check supplementary study file information
    raw_counts_files = StudyFile.where(study: populated_study, 'expression_file_info.is_raw_counts': true)
    assert_equal 1, raw_counts_files.count
    raw_counts_file = raw_counts_files.first
    assert_equal 'GRCm38', raw_counts_file.genome_assembly.name
    assert_equal 'Ensembl 94', raw_counts_file.genome_annotation.name

    # wait for ingest to complete and validate
    expected_cells = 1.upto(130).map { |cell| "AF_#{cell}" }
    wait_interval = 30
    max_wait = 300
    seconds_slept = 0
    sleep wait_interval
    seconds_slept += wait_interval
    until @study.study_files.where(:file_type.in => StudyFile::PARSEABLE_TYPES)
                            .pluck(:parse_status).all? { |status| ['parsed', 'failed'].include?(status) }
      puts "checking for parse completion after #{seconds_slept} seconds"
      @study.study_files.each do |file|
        print "#{file.upload_file_name} is #{file.parse_status}; "
      end
      if seconds_slept >= max_wait
        raise "After #{seconds_slept} seconds not all files have completed parsing"
      else
        puts "checking again in #{wait_interval} seconds"
        sleep wait_interval
        seconds_slept += wait_interval
        @study.reload
      end
    end

    puts 'All parse jobs completed!'

    # validate success
    @study.study_files.where(:file_type.in => StudyFile::PARSEABLE_TYPES).each do |study_file|
      study_file.reload
      assert study_file.parsed?, "#{study_file.upload_file_name} is not parsed"
      refute study_file.queued_for_deletion,
             "#{study_file.upload_file_name} has failed parsing, object is queued for deletion"
    end

    exp_cells = @study.all_expression_matrix_cells
    all_cells = @study.all_cells_array
    assert_equal expected_cells, exp_cells,
                 "Expression matrix cells not as expected; #{expected_cells} != #{exp_cells}"
    assert_equal expected_cells, all_cells,
                 "All matrix cells not as expected; #{expected_cells} != #{all_cells}"
  end
end
