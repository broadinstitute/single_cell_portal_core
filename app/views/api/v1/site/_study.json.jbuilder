json.set! :accession, study.accession
json.set! :name, study.name
json.set! :description, study.description
json.set! :full_description, study.full_description
json.set! :public, study.public
json.set! :detached, study.detached
json.set! :cell_count, study.cell_count
json.set! :gene_count, study.gene_count
if study.detached?
  json.set! :study_files, 'Unavailable (cannot load study workspace or bucket)'
else
  json.study_files study.study_files.downloadable, partial: 'api/v1/site/study_file', as: :study_file, locals: {study: study}
  json.directory_listings study.directory_listings.are_synced, partial: 'api/v1/site/directory_listing', as: :directory_listing, locals: {study: study}
end
json.external_resources do
  json.array! study.external_resources do |external_resource|
    json.set! :title, external_resource.title
    json.set! :description, external_resource.description
    json.set! :url, external_resource.url
    json.set! :publication_url, external_resource.publication_url
  end
end
