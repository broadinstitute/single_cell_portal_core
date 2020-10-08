require "test_helper"

class StudyFileTest < ActiveSupport::TestCase

  # load objects and set flags accordingly for test
  def setup
    @study = Study.first
    @expression_matrix = @study.expression_matrix_files.first
    @expression_matrix.update(parse_status: 'parsed')
    @metadata_file = @study.metadata_file
    @metadata_file.update(parse_status: 'parsing')
    @cluster_file = @study.cluster_ordinations_files.first
    @cluster_file.update(parse_status: 'parsing')
    @cluster = @study.cluster_groups.first
    @cluster.update(is_subsampling: true)
  end

  test 'should prevent deletion of study files during parsing or subsampling' do
    puts "#{File.basename(__FILE__)}: '#{self.method_name}'"

    # expression matrix is parsed, so it should be deletable
    assert @expression_matrix.can_delete_safely?,
           'Did not correctly return true for a parsed expression matrix'

    # cluster/metadata files should not be deletable yet as they are parsing
    refute @metadata_file.can_delete_safely?,
           'Metadata file is still parsing and should not be deletable'
    refute @cluster_file.can_delete_safely?,
           'Metadata file is still parsing and should not be deletable'

    # once parsing completes, because the cluster is subsampling, they should still not be deletable
    @study.study_files.where(:file_type.in => %w(Cluster Metadata)).update_all(parse_status: 'parsed')
    refute @metadata_file.can_delete_safely?,
           'Metadata file is still subsampling and should not be deletable'
    refute @cluster_file.can_delete_safely?,
           'Metadata file is still subsampling and should not be deletable'

    # once cluster is subsampled, both files should be deletable
    @cluster.update(subsampled: true, is_subsampling: false)
    # need to call reload to refresh cached object
    @metadata_file.reload
    @cluster_file.reload
    assert @metadata_file.can_delete_safely?,
           'Metadata file is no longer parsing/subsampling and should be deletable'
    assert @cluster_file.can_delete_safely?,
           'Metadata file is no longer parsing/subsampling and should be deletable'

    puts "#{File.basename(__FILE__)}: '#{self.method_name}' successful!"
  end

  test 'expression file data validates' do
    # note that we don't (and shouldn't) actually *save* anything in this test,
    # so we use throwaway objects and ids.
    puts "#{File.basename(__FILE__)}: '#{self.method_name}'"

    invalid_study_file = StudyFile.new(
      study: Study.new,
      file_type: 'Expression Matrix',
      name: 'test_exp_validate',
      taxon_id: Taxon.new.id,
      expression_file_info: ExpressionFileInfo.new(
        units: 'bad_value',
        library_construction_protocol: 'Mars-seq',
        is_raw_counts: true
      )
    )
    assert_equal false, invalid_study_file.valid?
    assert_equal({expression_file_info: ["is invalid"]}, invalid_study_file.errors.messages)

    valid_study_file = StudyFile.new(
      study: Study.new,
      file_type: 'Expression Matrix',
      name: 'test_exp_validate',
      taxon_id: Taxon.new.id,
      expression_file_info: ExpressionFileInfo.new(
        units: 'raw counts',
        library_construction_protocol: 'MARS-seq',
        is_raw_counts: true
      )
    )
    assert_equal true, valid_study_file.valid?
  end
end
