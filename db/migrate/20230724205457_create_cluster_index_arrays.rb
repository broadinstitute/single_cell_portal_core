class CreateClusterIndexArrays < Mongoid::Migration
  def self.up
    accessions = Study.pluck(:accession)
    accessions.each do |accession|
      study = Study.find_by(accession:)
      study.delay.create_all_cluster_cell_indices!
    end
  end

  def self.down
    cluster_file_ids = StudyFile.where(file_type: 'Cluster').pluck(:id)
    cluster_ids = ClusterGroup.pluck(:id)
    study_ids = Study.pluck(:id)
    DataArray.where(
      name: 'index', array_type: 'cells', linear_data_type: 'ClusterGroup', :linear_data_id.in => cluster_ids,
      :study_ids.in => study_ids, :study_file_ids.in => cluster_file_ids
    ).delete_all
  end
end
