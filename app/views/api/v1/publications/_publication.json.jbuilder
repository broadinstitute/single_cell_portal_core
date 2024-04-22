publication.attributes.each do |name, value|
  unless name == '_id' && !publication.persisted?
    json.set! name, value
  end
end
