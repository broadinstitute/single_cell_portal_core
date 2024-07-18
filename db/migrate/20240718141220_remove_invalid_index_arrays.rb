class RemoveInvalidIndexArrays < Mongoid::Migration
  def self.up
    # clean out any duplicate cell name index arrays that were a result of the cluster changing names
    bad_arrays = 0
    ClusterGroup.where(indexed: true, use_default_index: false).each do |cluster|
      study = cluster.study
      study_file = cluster.study_file
      query = {
        study_id: study.id, study_file_id: study_file.id, linear_data_type: 'ClusterGroup',
        linear_data_id: cluster.id, name: 'index', array_type: 'cells',
        :cluster_name.ne => cluster.name
      }
      arrays = DataArray.where(query)
      if arrays.any?
        count = arrays.count
        Rails.logger.info "#{cluster.name} has #{count} invalid arrays"
        bad_arrays += count
        arrays.delete_all
      end
    end
    puts "Completed: total arrays removed: #{bad_arrays}"
  end

  def self.down
    # non-reversible
  end
end
