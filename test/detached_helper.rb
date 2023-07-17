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
