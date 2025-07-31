class SetCloudProjectsForStudies < Mongoid::Migration
  def self.up
    Study.where(detached: false, cloud_project: nil).map(&:set_terra_cloud_project)
  end

  def self.down
    Study.update_all(cloud_project: nil, terra_study: false)
  end
end
