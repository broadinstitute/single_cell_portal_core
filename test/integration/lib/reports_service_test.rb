require 'test_helper'

class ReportsServiceTest < ActiveSupport::TestCase

  before(:all) do
    @user = FactoryBot.create(:user, test_array: @@users_to_clean)
    @user2 = FactoryBot.create(:user, test_array: @@users_to_clean)
    @basic_study = FactoryBot.create(:detached_study,
                                     name_prefix: 'report service test',
                                     test_array: @@studies_to_clean,
                                     public: false,
                                     user: @user)
    @study_metadata_file = FactoryBot.create(:metadata_file,
                                             use_metadata_convention: true,
                                             name: 'metadata.txt',
                                             study: @basic_study)

    @study_expression_file = FactoryBot.create(:expression_file,
                                               expression_file_info: {
                                                 is_raw_counts: true,
                                                 units: 'raw counts',
                                                 library_preparation_protocol: 'Drop-seq',
                                                 biosample_input_type: 'Whole cell',
                                                 modality: 'Proteomic'
                                               },
                                               name: 'expression.txt',
                                               study: @basic_study)
    @study_cluster_file = FactoryBot.create(
      :cluster_file,
      name: 'clusterA.txt',
      study: @basic_study,
      cell_input: { x: [1, 4, 6], y: [7, 5, 3], cells: %w[A B C D] },
      annotation_input: [{ name: 'foo', type: 'group', values: %w[bar bar baz baz] }]
    )

    @de_result = DifferentialExpressionResult.create(
      study: @basic_study, cluster_group: @basic_study.cluster_groups.by_name('clusterA.txt'),
      matrix_file_id: @study_expression_file.id, annotation_name: 'foo', annotation_scope: 'cluster',
      observed_values: %w[bar baz]
    )
  end

  test 'study_data return array of hashes with correct study information' do
    report_data = ReportsService.study_data
    assert_equal Study.where(queued_for_deletion: false).count, report_data.count
    basic_study_row = report_data.select {|r| r[:id] == @basic_study.id}.first
    assert_equal @basic_study.accession, basic_study_row[:accession]
    assert_equal @user.email, basic_study_row[:owner_email]
    assert_equal 'test.edu', basic_study_row[:owner_domain]
    assert_equal true, basic_study_row[:metadata_convention]
    assert_equal true, basic_study_row[:has_raw_counts]
    assert_nil basic_study_row[:last_initialized]
    assert_nil basic_study_row[:last_public]

    # check that the public history column correctly reflect updates
    @basic_study.update!(public: true)
    report_data = ReportsService.study_data
    basic_study_row = report_data.select {|r| r[:id] == @basic_study.id}.first
    last_public_time = basic_study_row[:last_public]
    assert last_public_time > 1.minute.ago
    assert last_public_time < 1.minute.from_now

    @basic_study.update!(public: false)

    @basic_study.update!(public: true)
    report_data = ReportsService.study_data
    basic_study_row = report_data.select {|r| r[:id] == @basic_study.id}.first
    assert basic_study_row[:last_public] > last_public_time
  end

  test 'differential_expression report contains correct info' do
    report_data = ReportsService.differential_expression_report
    de_entry = report_data.first
    ReportsService::REPORTS[:differential_expression][:data_columns].each do |attribute_name|
      # timestamp comparison is not useful as milliseconds get floored and won't match
      next if attribute_name == :created_at

      reported_value = de_entry[attribute_name]
      reference = attribute_name == :accession ? @basic_study : @de_result
      assert_equal reference.send(attribute_name), reported_value
    end
  end

  test 'get_report returns tsv' do
    report_string = ReportsService.get_report_data('studies', view_context: false)
    assert report_string.starts_with?(ReportsService::REPORTS[:studies][:data_columns].join("\t"))
    assert report_string.include?(@user.email)

    report_string = ReportsService.get_report_data('differential_expression', view_context: false)
    assert report_string.starts_with?(ReportsService::REPORTS[:differential_expression][:data_columns].join("\t"))
    assert report_string.include?('foo')
    assert report_string.include?('bar, baz')
    assert report_string.include?('clusterA.txt')
  end
end
