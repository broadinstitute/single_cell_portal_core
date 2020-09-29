ENV["RAILS_ENV"] = "test"
require File.expand_path("../../config/environment", __FILE__)
require "rails/test_help"

# upload a large file (i.e. > 10MB) from the test_data directory to a study
# simulates chunked upload by streaming file in 10MB chunks and then uploading in series
def perform_chunked_study_file_upload(filename, study_file_params, study_id)
  source_file = File.open(Rails.root.join('test', 'test_data', filename))
  upload_response = nil
  while chunk = source_file.read(10.megabytes)
    file_upload = Rack::Test::UploadedFile.new(StringIO.new(chunk), original_filename: filename) # mock original_filename header
    study_file_params[:study_file].merge!(upload: file_upload)
    upload_response = patch "/single_cell/studies/#{study_id}/upload", params: study_file_params, headers: {'Content-Type' => 'multipart/form-data'}
  end
  upload_response
end

# upload a file from the test_data directory to a study
def perform_study_file_upload(filename, study_file_params, study_id)
  file_upload = Rack::Test::UploadedFile.new(Rails.root.join('test', 'test_data', filename))
  study_file_params[:study_file].merge!(upload: file_upload)
  patch "/single_cell/studies/#{study_id}/upload", params: study_file_params, headers: {'Content-Type' => 'multipart/form-data'}
end

# start parsing a file from the test_data directory to a study
def initiate_study_file_parse(filename, study_id)
  study_file_params = {file: filename}
  post "/single_cell/studies/#{study_id}/parse", params: study_file_params, headers: {'Content-Type' => 'multipart/form-data'}, xhr: true
end

# configure omniauth response for a given user
def auth_as_user(user)
  OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new({
                                                                         :provider => 'google_oauth2',
                                                                         :uid => user.uid,
                                                                         :email => user.email
                                                                     })
end

def get_bq_row_count(bq_dataset, study)
  bq_dataset.query("SELECT COUNT(*) count FROM #{CellMetadatum::BIGQUERY_TABLE} WHERE study_accession = '#{study.accession}'", cache: false)[0][:count]
end
