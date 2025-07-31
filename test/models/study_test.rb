require 'test_helper'

class StudyTest < ActiveSupport::TestCase

  before(:all) do
    @user = FactoryBot.create(:admin_user, registered_for_firecloud: true, test_array: @@users_to_clean)
    @study = FactoryBot.create(:detached_study, user: @user, name_prefix: 'Study Test', test_array: @@studies_to_clean)
    StudyShare.create!(email: 'my-user-group@firecloud.org', permission: 'Reviewer', study: @study,
                       firecloud_project: @study.firecloud_project, firecloud_workspace: @study.firecloud_workspace)
    @exp_matrix = FactoryBot.create(:study_file,
                                    name: 'dense.txt',
                                    file_type: 'Expression Matrix',
                                    study: @study)
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

  after(:all) do
    Study.where(firecloud_workspace: 'bucket-read-check-test').delete_all
  end

  test 'should honor case in gene search within study' do
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
  end

  test 'should skip permission and group check during firecloud service outage' do
    # assert that under normal conditions user has compute permissions
    # use mocks globally for orchestration calls as we only need to test logic for skipping upstream call
    user = @study.user
    workspace_acl = {
      acl: { user.email => { accessLevel: 'WRITER', canCompute: true, canShare: true, pending: false } }
    }.with_indifferent_access
    ok_status_mock = Minitest::Mock.new
    ok_status_mock.expect :services_available?, true, @services_args
    ok_status_mock.expect :get_workspace_acl,
                          workspace_acl,
                          [@study.firecloud_project, @study.firecloud_workspace]
    ApplicationController.stub :firecloud_client, ok_status_mock do
      compute_permission = @study.can_compute?(user)
      assert compute_permission,
             "Did not correctly get compute permissions for #{user.email}, can_compute? should be true but found #{compute_permission}"
      ok_status_mock.verify
    end

    group_mock = Minitest::Mock.new
    group_mock.expect :get_user_groups, @user_groups
    services_mock = Minitest::Mock.new
    services_mock.expect :services_available?, true, @services_args
    FireCloudClient.stub :new, group_mock do
      ApplicationController.stub :firecloud_client, services_mock do
        in_group_share = @study.user_in_group_share?(user, 'Reviewer')
        group_mock.verify
        services_mock.verify
        assert in_group_share, "Did not correctly pick up group share, expected true but found #{in_group_share}"
      end
    end

    outage_status_mock = Minitest::Mock.new
    outage_status_mock.expect :services_available?, false, @services_args
    outage_status_mock.expect :services_available?, false, @services_args
    ApplicationController.stub :firecloud_client, outage_status_mock do
      compute_in_outage = @study.can_compute?(user)
      group_share_in_outage = @study.user_in_group_share?(user, 'Reviewer')

      # only verify once, as we expect :services_available? was called twice now
      outage_status_mock.verify
      refute compute_in_outage, "Should not have compute permissions in outage, but can_compute? is #{compute_in_outage}"
      refute group_share_in_outage, "Should not have group share in outage, but user_in_group_share? is #{group_share_in_outage}"
    end
  end

  test 'should default to first available annotation' do
    user = FactoryBot.create(:user, test_array: @@users_to_clean)
    study = FactoryBot.create(:detached_study,
                              name_prefix: 'Default Annotation Test',
                              user: user,
                              test_array: @@studies_to_clean)
    assert study.default_annotation.nil?
    FactoryBot.create(:metadata_file,
                      name: 'metadata.txt',
                      study: study,
                      cell_input: %w[A B C],
                      annotation_input: [
                        { name: 'species', type: 'group', values: %w[dog dog dog] }
                      ])
    assert_equal 'species--group--study', study.default_annotation
  end

  test 'should ignore email case for share checking' do
    study = FactoryBot.create(:detached_study,
                              name_prefix: 'Share Case Test',
                              user: @user,
                              test_array: @@studies_to_clean)
    share_user = FactoryBot.create(:user, test_array: @@users_to_clean)
    invalid_email = share_user.email.upcase
    share = study.study_shares.build(permission: 'View', email: invalid_email)
    share.save!
    assert share.present?
    assert_equal invalid_email, share.email
    refute share.email == share_user.email
    assert study.can_view?(share_user)
  end

  # ensure that user-specified data embargoes expire on the date given
  test 'should lift embargo on date specified' do
    study = FactoryBot.create(:detached_study,
                              name_prefix: 'Embargo Test',
                              user: @user,
                              test_array: @@studies_to_clean)
    user = FactoryBot.create(:user, test_array: @@users_to_clean)
    assert_not study.embargo_active?
    assert_not study.embargoed?(user)
    today = Time.zone.today
    study.update(embargo: today + 1.week)
    assert study.embargo_active?
    assert study.embargoed?(user)
    # ensure users with direct access are still not embargoed
    assert_not study.embargoed?(study.user)
    # ensure embargo lifts on specified date
    study.update(embargo: today)
    assert_not study.embargo_active?
    assert_not study.embargoed?(user)
  end

  test 'should check bucket read access' do
    # stub detached to allow method to fire after the fact via direct invocation (doesn't execute for detached studies)
    # there's no way to verify the mock on a background process hence the :check_bucket_read_access_without_delay
    study = FactoryBot.create(:detached_study,
                              name_prefix: 'Bucket Read Access Test',
                              user: @user,
                              test_array: @@studies_to_clean)
    mock = Minitest::Mock.new
    mock.expect :check_bucket_read_access,
                true,
                [study.firecloud_project, study.firecloud_workspace]
    FireCloudClient.stub :new, mock do
      study.stub :detached, false do
        study.check_bucket_read_access_without_delay
        mock.verify
      end
    end
  end

  test 'should load expression matrix cells by file type' do
    genes = %w[farsa phex]
    cells = %w[cellA cellB cellC]
    expression_input = genes.index_with(cells.map {|c| [c, rand.floor(3)]})
    dense_matrix = FactoryBot.create(:expression_file, study: @study, name: 'dense_matrix.tsv', expression_input:)
    ann_data_file = FactoryBot.create(:ann_data_file,
                                      study: @study,
                                      name: 'test.h5ad',
                                      reference_file: false,
                                      cell_input: cells,
                                      expression_input:)
    assert_equal cells, @study.expression_matrix_cells(dense_matrix)
    assert_equal cells, @study.expression_matrix_cells(ann_data_file)
    assert_equal cells, @study.expression_matrix_cells(ann_data_file, matrix_type: 'processed')
    assert_equal cells, @study.expression_matrix_cells(ann_data_file, matrix_type: 'raw')
  end

  test 'should prevent data embargo longer than max' do
    study = FactoryBot.create(:detached_study, user: @user, name_prefix: 'Embargo Test', test_array: @@studies_to_clean)
    assert study.valid?
    study.embargo = study.max_embargo + 1.day
    assert_not study.valid?
    assert study.errors.has_key?(:embargo)
    study.public = false
    assert study.valid?
  end

  test 'should determine if a study was just published/initialized' do
    study = FactoryBot.create(:detached_study,
                              user: @user,
                              name_prefix: 'State Test',
                              public: false,
                              test_array: @@studies_to_clean)
    assert_not study.was_just_published?
    assert_not study.was_just_initialized?
    study.update(public: true)
    assert study.was_just_published?
    assert_equal study.updated_at.to_s, study.last_public_date.to_s
    assert study.last_change_for(:public).present?
    study.update(initialized: true)
    assert study.was_just_initialized?
    assert_equal study.updated_at.to_s, study.last_initialized_date.to_s
    assert study.last_change_for(:initialized).present?
  end

  test 'should set cell count on AnnData file' do
    study = FactoryBot.create(:detached_study,
                              user: @user,
                              name_prefix: 'AnnData Cell Count Test',
                              test_array: @@studies_to_clean)
    cells = %w[A B C D]
    ann_data_file = FactoryBot.create(:ann_data_file,
                                      study:,
                                      name: 'test.h5ad',
                                      cell_input: cells,
                                      annotation_input: [
                                        { name: 'disease', type: 'group', values: %w[cancer cancer normal normal] }
                                      ])
    study.set_cell_count
    assert_equal 4, study.cell_count
    # manually unset cell count and set file to 'parsing' to simulate race condition
    study.update(cell_count: 0)
    assert_equal 0, study.cell_count
    ann_data_file.update(parse_status: 'parsing')
    study.set_cell_count
    assert_equal 4, study.cell_count
  end

  test 'should update cluster order' do
    study = FactoryBot.create(:detached_study,
                              user: @user,
                              name_prefix: 'Cluster Order Test',
                              test_array: @@studies_to_clean)
    assert_empty study.default_cluster_order
    cell_input = {
      x: [1, 4, 6],
      y: [7, 5, 3],
      cells: %w(A B C)
    }
    FactoryBot.create(:cluster_file, name: 'cluster_example.txt', study:, cell_input:)
    cluster = study.cluster_groups.first
    study.update_cluster_order(cluster, action: :append)
    study.reload
    assert_equal [cluster.name], study.default_cluster_order
    FactoryBot.create(:cluster_file, name: 'cluster_2_example.txt', study:, cell_input:)
    new_cluster = study.cluster_groups.last
    study.update_cluster_order(new_cluster, action: :append)
    study.reload
    assert_equal [cluster.name, new_cluster.name], study.default_cluster_order
  end
end
