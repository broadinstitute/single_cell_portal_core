class CreateSyntheticBrandingGroups < Mongoid::Migration
  def self.up
    unless Rails.env == 'production'
      SyntheticBrandingGroupPopulator.populate_all
    end
  end

  def self.down
    unless Rails.env == 'production'
      SyntheticBrandingGroupPopulator.remove_all
    end
  end
end
