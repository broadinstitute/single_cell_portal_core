saved_view.attributes.each do |name, value|
  unless name == '_id' && !saved_view.persisted?
    json.set! name, value
  end
end
json.set! :href, saved_view.href
