bookmark.attributes.each do |name, value|
  unless name == '_id' && !bookmark.persisted?
    json.set! name, value
  end
end
json.set! :link, bookmark.link
json.set! :href, bookmark.href
