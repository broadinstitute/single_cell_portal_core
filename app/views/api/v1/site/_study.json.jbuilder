json.set! :accession, study.accession
json.set! :name, study.name
json.set! :description, study.description
json.set! :full_description, study.full_description
json.set! :public, study.public
json.set! :detached, study.detached
json.set! :cell_count, study.cell_count
json.set! :gene_count, study.gene_count
if study.detached
  json.set! :study_files, 'Unavailable (cannot load study workspace or bucket)'
else
  json.study_files study.study_files, partial: 'api/v1/site/study_file', as: :study_file, locals: {study: study}
end
