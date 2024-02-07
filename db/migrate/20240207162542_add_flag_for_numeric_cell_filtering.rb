class AddFlagForNumericCellFiltering < Mongoid::Migration
  def self.up
    FeatureFlag.create!(name: 'show_numeric_cell_filtering',
                        default_value: false,
                        description: 'show numeric cell filtering')
  end

  def self.down
    FeatureFlag.find_by(name: 'show_numeric_cell_filtering')&.destroy
  end
end
