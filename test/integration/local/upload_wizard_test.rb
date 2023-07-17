require 'integration_test_helper'
require 'test_helper'
require 'includes_helper'
require 'detached_helper'

class UploadWizardTest < ActionDispatch::IntegrationTest

  before(:all) do
    @user = FactoryBot.create(:user, test_array: @@users_to_clean)
    @study = FactoryBot.create(:detached_study,
                               name_prefix: 'Upload Wizard Test',
                               public: false,
                               user: @user,
                               test_array: @@studies_to_clean)
  end

  # ensures the upload wizard will render, regardless of the state of the study in terms of how many files have
  # already been uploaded.  used as a smoke test for changes to the upload wizard state logic
  test 'can render upload wizard' do
    mock_not_detached @study, :find do
      sign_in @user
      auth_as_user @user
      # empty study
      get initialize_study_path(@study.id)
      assert_response :success

      FactoryBot.create(:metadata_file,
                        name: 'metadata.txt', study: @study,
                        cell_input: %w[A B C],
                        annotation_input: [
                          { name: 'species', type: 'group', values: %w[dog cat dog] },
                          { name: 'disease', type: 'group', values: %w[none none measles] }
                        ])
      @study.reload
      assert @study.metadata_file.present?
      get initialize_study_path(@study.id)
      assert_response :success

      FactoryBot.create(:cluster_file,
                        name: 'cluster_1.txt', study: @study,
                        cell_input: {
                          x: [1, 4, 6],
                          y: [7, 5, 3],
                          cells: %w[A B C]
                        },
                        cluster_type: '2d')
      @study.reload
      assert @study.cluster_ordinations_files.any?
      get initialize_study_path(@study.id)
      assert_response :success

      raw_matrix = FactoryBot.create(:study_file, name: 'raw.txt', file_type: 'Expression Matrix', study: @study)
      raw_matrix.build_expression_file_info(is_raw_counts: true, units: 'raw counts',
                                            library_preparation_protocol: 'MARS-seq',
                                            modality: 'Transcriptomic: unbiased',
                                            biosample_input_type: 'Whole cell')
      raw_matrix.save
      @study.reload
      assert @study.expression_matrix_files.any?
      get initialize_study_path(@study.id)
      assert_response :success

      processed_matrix = FactoryBot.create(:study_file, name: 'proccessed.txt', file_type: 'Expression Matrix', study: @study)
      processed_matrix.build_expression_file_info(is_raw_counts: false, raw_counts_associations: [raw_matrix.id.to_s],
                                                  library_preparation_protocol: 'MARS-seq',
                                                  modality: 'Transcriptomic: unbiased',
                                                  biosample_input_type: 'Whole cell')
      processed_matrix.save
      @study.reload
      assert @study.expression_matrix_files.count == 2
      get initialize_study_path(@study.id)
      assert_response :success
    end
  end
end
