json.set! :name, directory_listing.name
json.set! :description, directory_listing.description
json.set! :file_type, directory_listing.file_type
json.set! :download_url, api_v1_bulk_download_generate_curl_config_url(accessions: directory_listing.study.accession,
                                                         directory: directory_listing.name)
json.set! :files, directory_listing.files
