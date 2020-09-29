study.attributes.each do |name, value|
  unless name == '_id' && !study.persisted?
    json.set! name, value
  end
end
json.set! :full_description, study.full_description if show_full_description
