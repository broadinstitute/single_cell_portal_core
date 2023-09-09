class AddFlagForUserDeUpload < Mongoid::Migration
  def self.up
    FeatureFlag.create!(name: 'show_cell_facet_filtering',
                        default_value: false,
                        description: 'show the cell facet filtering button')
  end

  def self.down
    FeatureFlag.find_by(name: 'show_cell_facet_filtering')&.destroy
  end
end
