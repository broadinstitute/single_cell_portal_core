class AutoPopulateSpeciesInfo < Mongoid::Migration
  def self.up
    admin_user = User.where(admin: true).first
    taxons = File.open(Rails.root.join('lib', 'assets', 'default_species_assemblies.txt'))
    if File.exist?(taxons) && admin_user.present?
      Taxon.parse_from_file(path, admin_user)
    end
  end

  def self.down
    Taxon.destroy_all
  end
end
