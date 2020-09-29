require "integration_test_helper"

class SyntheticStudyPopulatorTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test 'should be able to populate a study with convention metadata' do
    SYNTH_STUDY_INFO = {
      name: 'HIV in bovine blood',
      folder: 'cow_blood'
    }

    # SyntheticStudyPopulator does have logic for deleting existing sutdies on populate
    # but this is for belt-and-suspenders to make sure the delete is successful
    if Study.find_by(name: SYNTH_STUDY_INFO[:name])
      Study.find_by(name: SYNTH_STUDY_INFO[:name]).destroy_and_remove_workspace
    end

    assert_nil Study.find_by(name: SYNTH_STUDY_INFO[:name])

    SyntheticStudyPopulator.populate(SYNTH_STUDY_INFO[:folder])
    populated_study = Study.find_by(name: SYNTH_STUDY_INFO[:name])

    assert_not_nil populated_study
    assert_equal 1, populated_study.study_files.count
    assert_equal 'Metadata', populated_study.study_files.first.file_type

    # note that we're not testing the ingest process yet due to timing concerns
    Study.find_by(name: SYNTH_STUDY_INFO[:name]).destroy_and_remove_workspace
  end
end
