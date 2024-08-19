class SyncExpFileInfoForAnnData < Mongoid::Migration
  def self.up
    StudyFile.where(file_type: 'AnnData').each do |study_file|
      study_file.ann_data_file_info.update_expression_file_info
    end
  end

  def self.down
    # non-reversible
  end
end
