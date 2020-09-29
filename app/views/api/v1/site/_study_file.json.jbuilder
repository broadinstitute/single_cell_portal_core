json.set! :name, study_file.name
json.set! :file_type, study_file.file_type
json.set! :description, study_file.description
json.set! :bucket_location, study_file.bucket_location
json.set! :upload_file_size, study_file.upload_file_size
if study_file.human_fastq_url.present?
  json.set! :download_url, study_file.human_fastq_url
else
  json.set! :download_url, api_v1_site_study_download_data_url(accession: study.accession, filename: study_file.bucket_location)
  json.set! :media_url, api_v1_site_study_stream_data_url(accession: study.accession, filename: study_file.bucket_location)
end
