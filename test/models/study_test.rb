require 'test_helper'
require 'detached_helper'

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

  teardown do
    @study.reload
  end

  after(:all) do
    Study.where(:firecloud_workspace.in => %w[bucket-read-check-test add-internal-workspace-test]).delete_all
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

    group_mock = MiniTest::Mock.new
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
    mock.expect :check_bucket_read_access,
                true,
                [FireCloudClient::PORTAL_NAMESPACE, study.internal_workspace]
    FireCloudClient.stub :new, mock do
      study.stub :detached, false do
        study.check_bucket_read_access_without_delay
        mock.verify
      end
    end
  end

  test 'should return proper API client' do
    assert_equal ApplicationController.firecloud_client, @study.workspace_client

    @study.firecloud_project = 'foo'
    workspace_client = @study.workspace_client
    assert_equal 'foo', workspace_client.project
    assert_equal @user.access_token[:access_token], workspace_client.access_token[:access_token]
  end

  test 'should assign internal workspace name' do
    assert @study.internal_workspace =~ /#{@study.accession}-test-internal/
  end

  test 'should load google bucket name' do
    assert_equal @study.bucket_id, @study.google_bucket_name(:study)
    assert_equal @study.internal_bucket_id, @study.google_bucket_name(:internal)
  end

  test 'should check user workspace and billing project access' do
    mock = Minitest::Mock.new
    acl = {
      acl: {
        @user.email => {
          accessLevel: 'WRITER', canCompute: false, canShare: true, pending: false
        }
      }
    }
    mock.expect :get_workspace_acl, acl, [String, String]
    ApplicationController.stub :firecloud_client, mock do
      assert @study.user_has_workspace_access?
      mock.verify
    end

    user_client_mock = Minitest::Mock.new
    project_name = 'my-billing-project'
    projects = [{ projectName: project_name, status: 'Ready', roles: %w[Owner] }.with_indifferent_access]
    user_client_mock.expect :get_workspace_acl, { acl: {} }, [String, String]
    user_client_mock.expect :get_billing_projects, projects
    user_client_mock.expect :get_billing_projects, projects
    FireCloudClient.stub :new, user_client_mock do
      @study.firecloud_project = project_name
      assert @study.user_has_workspace_access?
      assert @study.billing_project_ok?
      user_client_mock.verify
    end
  end

  # new test to cover workspace creation sub-methods
  test 'should create workspace assign workspace acls' do
    mock = Minitest::Mock.new
    owner_group = { groupEmail: 'sa-owner-group@firecloud.org' }.with_indifferent_access
    admin_group = { groupEmail: "#{FireCloudClient::ADMIN_INTERNAL_GROUP_NAME}@firecloud.org" }.with_indifferent_access
    assign_workspace_mock!(mock, owner_group, @study.firecloud_workspace, skip_entities: true)
    AdminConfiguration.stub :find_or_create_ws_user_group!, owner_group do
      AdminConfiguration.stub :find_or_create_admin_internal_group!, admin_group do
        ApplicationController.stub :firecloud_client, mock do
          @study.stub :detached, false do
            Parallel.map([:study, :internal], in_threads: 2) do |workspace_type|
              @study.create_and_validate_workspace(workspace_type)
            end
            assert_not @study.errors.any?
            mock.verify
          end
        end
      end
    end
  end

  test 'should create internal workspace for existing study' do
    study = Study.create(name: 'Add Internal Workspace Test', detached: true, user: @user)
    mock = Minitest::Mock.new
    project = FireCloudClient::PORTAL_NAMESPACE
    workspace = {
      name: "#{study.accession}-test-internal-#{SecureRandom.alphanumeric(5)}",
      bucketName: SecureRandom.uuid
    }.with_indifferent_access
    owner_email = 'sa-owner-group@firecloud.org'
    owner_group = { groupEmail: owner_email }.with_indifferent_access
    admin_email = "#{FireCloudClient::ADMIN_INTERNAL_GROUP_NAME}@firecloud.org"
    admin_group = { groupEmail: admin_email }.with_indifferent_access
    owner_acl = { acl: { owner_group[:groupEmail] => { accessLevel: 'OWNER' } } }.with_indifferent_access
    user_read_acl = { acl: { @user.email => { accessLevel: 'READER' } } }.with_indifferent_access
    admin_acl = { acl: { admin_group[:groupEmail] => { accessLevel: 'WRITER' } } }.with_indifferent_access
    mock.expect :workspace_exists?, false, [project, String]
    mock.expect :create_workspace, workspace, [project, String, true]
    mock.expect :create_workspace_acl, owner_acl, [owner_email, 'OWNER', true, false]
    mock.expect :update_workspace_acl, Hash, [project, String, owner_acl]
    mock.expect :get_workspace_acl, owner_acl, [project, String]
    mock.expect :create_workspace_acl, admin_acl, [admin_email, 'WRITER', true, false]
    mock.expect :update_workspace_acl, Hash, [project, String, admin_acl]
    mock.expect :create_workspace_acl, user_read_acl, [@user.email, 'READER', false, false]
    mock.expect :update_workspace_acl, Hash, [project, String, user_read_acl]
    mock.expect :check_bucket_read_access, true, [project, String]
    AdminConfiguration.stub :find_or_create_ws_user_group!, owner_group do
      AdminConfiguration.stub :find_or_create_admin_internal_group!, admin_group do
        ApplicationController.stub :firecloud_client, mock do
          study.stub :detached, false do
            study.add_internal_workspace
            assert study.valid?
            assert study.internal_workspace.start_with?("#{study.accession}-test-internal")
            assert_equal workspace[:bucketName], study.internal_bucket_id
            mock.verify
          end
        end
      end
    end
  end
end
