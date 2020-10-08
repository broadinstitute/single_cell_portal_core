require "test_helper"

class StudyTest < ActiveSupport::TestCase
  def setup
    @study = Study.first
    @exp_matrix = @study.expression_matrix_files.first
    # create genes & insert data; data is loaded here since test is self contained
    @gene_names = %w(Gad1 Gad2 Egfr Fgfr3 Clybl)
    @genes = {}
    iterator = 1.upto(5)
    @cells = iterator.map {|i| "cell_#{i}"}
    @values = iterator.to_a
    @gene_names.each do |gene|
      @genes[gene] = Gene.find_or_create_by!(name: gene, searchable_name: gene.downcase, study: @study,
                                             study_file: @exp_matrix)
      # add data for first genes to prove that correct gene is being loaded (beyond name matching)
      DataArray.find_or_create_by!(name: @genes[gene].cell_key, cluster_name: @exp_matrix.name, array_type: 'cells',
                                   array_index: 0, study_file: @exp_matrix, values: @cells,
                                   linear_data_type: 'Gene', linear_data_id: @genes[gene].id, study: @study)
      DataArray.find_or_create_by!(name: @genes[gene].score_key, cluster_name: @exp_matrix.name, array_type: 'expression',
                                   array_index: 0, study_file: @exp_matrix, values: @values,
                                   linear_data_type: 'Gene', linear_data_id: @genes[gene].id, study: @study)
      upcased_gene = gene.upcase
      # do not insert data for upcased genes
      @genes[upcased_gene] = Gene.find_or_create_by!(name: upcased_gene, searchable_name: upcased_gene.downcase,
                                                     study: @study, study_file: @exp_matrix)
    end

    # mock group list
    @user_groups = [{"groupEmail"=>"my-user-group@firecloud.org", "groupName"=>"my-user-group", "role"=>"Member"}]
    @services_args = [String, String, String]
  end

  test 'should honor case in gene search within study' do
    puts "#{File.basename(__FILE__)}: '#{self.method_name}'"

    gene_name = @gene_names.sample
    matrix_ids = @study.expression_matrix_files.pluck(:id)
    # search with case sensitivity first
    gene_1 = @study.genes.by_name_or_id(gene_name, matrix_ids)
    assert_equal gene_name, gene_1['name'],
                 "Did not return correct gene from #{gene_name}; expected #{gene_name} but found #{gene_1['name']}"
    expected_scores = Hash[@cells.zip(@values)]
    assert_equal expected_scores, gene_1['scores'],
                 "Did not load correct expression data from #{gene_name}; expected #{expected_scores} but found #{gene_1['scores']}"
    upper_case = gene_name.upcase
    gene_2 = @study.genes.by_name_or_id(upper_case, matrix_ids)
    assert_equal upper_case, gene_2['name'],
                 "Did not return correct gene from #{upper_case}; expected #{upper_case} but found #{gene_2['name']}"
    assert_empty gene_2['scores'],
                 "Found expression data for #{upper_case} when there should not have been; #{gene_2['scores']}"

    # now search without case sensitivity, should return the first gene found, which would be the same as original gene
    lower_case = gene_name.downcase
    gene_3 = @study.genes.by_name_or_id(lower_case, matrix_ids)
    assert_equal gene_name, gene_3['name'],
                 "Did not return correct gene from #{lower_case}; expected #{gene_name} but found #{gene_3['name']}"
    assert_equal expected_scores, gene_3['scores'],
                 "Did not load correct expression data from #{lower_case}; expected #{expected_scores} but found #{gene_3['scores']}"

    puts "#{File.basename(__FILE__)}: '#{self.method_name}' successful!"
  end

  test 'should skip permission and group check during firecloud service outage' do
    puts "#{File.basename(__FILE__)}: '#{self.method_name}'"

    # assert that under normal conditions user has compute permissions
    user = @study.user
    compute_permission = @study.can_compute?(user)
    assert compute_permission,
           "Did not correctly get compute permissions for #{user.email}, can_compute? should be true but found #{compute_permission}"

    # mock call to get groups to assert check happens in normal circumstances
    group_mock = MiniTest::Mock.new
    group_mock.expect :get_user_groups, @user_groups
    FireCloudClient.stub :new, group_mock do
      in_group_share = @study.user_in_group_share?(user, 'Reviewer')
      group_mock.verify
      assert in_group_share, "Did not correctly pick up group share, expected true but found #{in_group_share}"
    end

    # now simulate outage to prove checks do not happen and return false
    # each mock/expectation can only be used once, hence the duplicate declarations
    status_mock = Minitest::Mock.new
    status_mock.expect :services_available?, false, @services_args
    status_mock.expect :services_available?, false, @services_args
    ApplicationController.stub :firecloud_client, status_mock do
      compute_in_outage = @study.can_compute?(user)
      group_share_in_outage = @study.user_in_group_share?(user, 'Reviewer')

      # only verify once, as we expect :services_available? was called twice now
      status_mock.verify
      refute compute_in_outage, "Should not have compute permissions in outage, but can_compute? is #{compute_in_outage}"
      refute group_share_in_outage, "Should not have group share in outage, but user_in_group_share? is #{group_share_in_outage}"
    end

    puts "#{File.basename(__FILE__)}: '#{self.method_name}' successful!"
  end
end
