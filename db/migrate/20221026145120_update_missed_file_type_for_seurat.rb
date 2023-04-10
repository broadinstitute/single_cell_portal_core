class UpdateMissedFileTypeForSeurat < Mongoid::Migration
  def self.up

    # Missed migrating .RDS in the first migration so fixing that here
    StudyFile.where(:file_type.in => ['Documentation', 'Other', 'Analysis Output'], upload_file_name: /\.(RDS$)/).update_all(file_type: 'Seurat')

  end

  def self.down
    # intentially left blank
  end
end
