# load only the ActiveStorage::Filename class for use in filename sanitizing
# this is because we cannot load the full ActiveStorage engine as it is incompatible with Mongoid
require "active_storage"

base_require_path = Bundler.bundle_path.to_s + '/gems/activestorage-' + ActiveStorage.gem_version.to_s
class_filename = base_require_path + '/app/models/active_storage/filename.rb'
if File.exist?(class_filename)
  require_relative class_filename rescue NameError
end
