class AddCloudProjectToGenomeAnnotations < Mongoid::Migration
  def self.up
    GenomeAnnotation.all.each do |genome_annotation|
      genome_annotation.assign_cloud_project!
      genome_annotation.save(validate: false)
    end
  end

  def self.down
    GenomeAnnotation.update_all(cloud_project: nil)
  end
end
