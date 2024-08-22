class AddFlagForPathwayExpression < Mongoid::Migration
  def self.up
    FeatureFlag.create!(name: 'show_pathway_expression',
                        default_value: true,
                        description: 'show expression overlay in pathway diagrams')
  end

  def self.down
    FeatureFlag.find_by(name: 'show_pathway_expression')&.destroy
  end
end
