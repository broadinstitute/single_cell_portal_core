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
def generate_download_file_mock(study_files, parent_study: nil)
  download_file_mock = Minitest::Mock.new
  study_files.each do |file|
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
  expires = { expires: Integer }
  ValidationTools::SIGNED_URL_KEYS.each do |param|
    params << "#{param}=#{SecureRandom.uuid}"
  end
  mock_signed_url += params.join('&')
  mock.expect :download_bucket_file, mock_signed_url, [String, String], **expires
end

def assign_get_file_mock!(mock)
  file_mock = Minitest::Mock.new
  file_mock.expect :present?, true
  file_mock.expect :size, 1.megabyte
  mock.expect :load_study_bucket_file, file_mock, [String, String]
end

# helper to mock all calls to Terra orchestration API when saving a new study & creating workspace
# useful for when we don't want the study to be detached, but still want to save to the database
def assign_workspace_mock!(mock, group, study_name)
  workspace = { name: study_name, bucketName: SecureRandom.uuid }.with_indifferent_access
  owner_acl = { acl: { group[:groupEmail] => { accessLevel: 'OWNER' } } }.with_indifferent_access
  compute_acl = { acl: { @user.email => { accessLevel: 'WRITER', canCompute: true } } }.with_indifferent_access
  mock.expect :create_workspace, workspace, [String, String, true]
  mock.expect :create_workspace_acl, Hash, [String, String, true, false]
  mock.expect :update_workspace_acl, Hash, [String, String, Hash]
  mock.expect :get_workspace_acl, owner_acl, [String, String]
  mock.expect :create_workspace_acl, Hash, [String, String, true, true]
  mock.expect :update_workspace_acl, Hash, [String, String, Hash]
  mock.expect :get_workspace_acl, compute_acl, [String, String]
  mock.expect :import_workspace_entities_file, true, [String, String, File]
end

# helper to assign mocks for creating a study bucket
def assign_bucket_mock!(mock)
  mock.expect :create_study_bucket, Google::Cloud::Storage::Bucket, [String], **{ location: String }
  mock.expect :enable_bucket_autoclass, String, [String]
  mock.expect :update_study_bucket_acl, String, [String, String], **{ role: Symbol }
end
