# helper to mock a study not being detached
# useful for when we don't really need a workspace
def mock_not_detached(study, find_method, &block)
  return_val = find_method.to_sym == :any_of ? [study] : study
  Study.stub find_method, return_val do
    study.stub :detached?, false, &block
  end
end

# mock array of studies not being detached
# useful in bulk download/search tests
def mock_query_not_detached(studies, &block)
  Study.stub :where, studies do
    Study.stub :find_by, studies.first, &block
  end
end

# generate a mock with all necessary signed_url calls for an array of files to use with detached study
def generate_signed_urls_mock(study_files, parent_study: nil)
  urls_mock = Minitest::Mock.new
  study_files.each do |file|
    assign_url_mock!(urls_mock, file, parent_study:)
  end
  urls_mock
end

# adds :get_workspace_file to array of mock expects - useful for testing a user clicking download link
def generate_download_file_mock(study_files, parent_study: nil, private: false)
  download_file_mock = Minitest::Mock.new
  study_files.each do |file|
    assign_services_mock!(download_file_mock, private)
    assign_get_file_mock!(download_file_mock)
    assign_url_mock!(download_file_mock, file, parent_study:)
  end
  download_file_mock
end

def assign_url_mock!(mock, study_file, parent_study: nil)
  study = parent_study || study_file.study
  location = study_file.try(:bucket_location) || study_file
  mock_signed_url = "https://www.googleapis.com/storage/v1/b/#{study.bucket_id}/#{location}?"
  params = []
  ValidationTools::SIGNED_URL_KEYS.each do |param|
    params << "#{param}=#{SecureRandom.uuid}"
  end
  mock_signed_url += params.join('&')
  mock.expect :execute_gcloud_method, mock_signed_url, [:generate_signed_url, 0, String, String, Hash]
end

def assign_get_file_mock!(mock)
  file_mock = Minitest::Mock.new
  file_mock.expect :present?, true
  file_mock.expect :size, 1.megabyte
  mock.expect :execute_gcloud_method, file_mock, [:get_workspace_file, 0, String, String]
end

def assign_services_mock!(mock, private)
  if private
    # private file downloads have an extra call to :services_available? for Sam and Rawls in addition to GoogleBuckets
    mock.expect :services_available?, true, [String, String]
  end
  mock.expect :services_available?, true, [String]
end

# helper to mock all calls to Terra orchestration API when saving a new study & creating workspace
# useful for when we don't want the study to be detached, but still want to save to the database
def assign_workspace_mock!(mock, group, study_name, skip_entities: false)
  workspace = { name: study_name, bucketName: SecureRandom.uuid }.with_indifferent_access
  owner_acl = { acl: { group[:groupEmail] => { accessLevel: 'OWNER' } } }.with_indifferent_access
  compute_acl = { acl: { @user.email => { accessLevel: 'WRITER', canCompute: true } } }.with_indifferent_access
  user_read_acl = { acl: { @user.email => { accessLevel: 'READER' } } }.with_indifferent_access
  admin_group = "#{FireCloudClient::ADMIN_INTERNAL_GROUP_NAME}@firecloud.org"
  admin_acl = { acl: { admin_group => { accessLevel: 'WRITER' } } }.with_indifferent_access
  # we don't actually know in what order acls will be assigned as workspace creation happens in parallel
  # since Minitest cares about parameters for :expect, use a Set for the share/compute permissions to avoid
  # MockExpectationError from unexpected arguments
  permission_set = Set[true, false]
  mock.expect :create_workspace, workspace, [String, String, true]
  mock.expect :create_workspace_acl, Hash, [String, String, permission_set, permission_set]
  mock.expect :update_workspace_acl, owner_acl, [String, String, Hash]
  mock.expect :get_workspace_acl, owner_acl, [String, String]
  mock.expect :create_workspace_acl, Hash, [String, String, permission_set, permission_set]
  mock.expect :update_workspace_acl, owner_acl, [String, String, Hash]
  mock.expect :get_workspace_acl, owner_acl, [String, String]
  mock.expect :create_workspace_acl, Hash, [String, String, permission_set, permission_set]
  mock.expect :update_workspace_acl, admin_acl, [String, String, Hash]
  mock.expect :create_workspace_acl, Hash, [String, String, permission_set, permission_set]
  mock.expect :update_workspace_acl, compute_acl, [String, String, Hash]
  mock.expect :import_workspace_entities_file, true, [String, String, File] unless skip_entities
  mock.expect :create_workspace, workspace, [String, String, true]
  mock.expect :create_workspace_acl, Hash, [String, String, permission_set, permission_set]
  mock.expect :update_workspace_acl, user_read_acl, [String, String, Hash]
end
