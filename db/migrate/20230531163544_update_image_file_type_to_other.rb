  class UpdateImageFileTypeToOther < Mongoid::Migration
    def self.up

      StudyFile.where(:file_type => 'Image').update_all(file_type: 'Other')

    end

    def self.down
      # intentially left blank
    end
  end