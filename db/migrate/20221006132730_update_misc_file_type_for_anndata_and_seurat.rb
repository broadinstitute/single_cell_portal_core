  class UpdateMiscFileTypeForAnndataAndSeurat < Mongoid::Migration
    def self.up
      # For AnnData
      StudyFile.where(:file_type.in => ['Other', 'Documentation', 'Analysis Output'], upload_file_name: /\.(h5ad|h5)$/).update_all(file_type: 'AnnData')

      # For Seurat
      StudyFile.where(:file_type.in => ['Documentation', 'Other', 'Analysis Output'], upload_file_name: /\.(rda|Rda|rds|Rds|Rdata$)/).update_all(file_type: 'Seurat')

    end

    def self.down
      # intentially left blank
    end
  end