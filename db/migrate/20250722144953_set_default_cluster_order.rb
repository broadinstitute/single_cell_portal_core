class SetDefaultClusterOrder < Mongoid::Migration
  def self.up
    Study.all.each do |study|
      study.default_options[:cluster_order] = study.standard_cluster_groups.pluck(:name)
      study.default_options[:spatial_order] = study.spatial_cluster_groups.pluck(:name)
      study.save(validate: false) # Skip validations to avoid issues with older studies
    end
  end

  def self.down
    Study.all.each do |study|
      study.default_options[:cluster_order] = []
      study.default_options[:spatial_order] = []
      study.save(validate: false) # Skip validations to avoid issues with older studies
    end
  end
end
