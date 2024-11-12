class SetAnnDataExpressionLabel < Mongoid::Migration
  def self.up
    study_files = StudyFile.where(file_type: 'AnnData', 'ann_data_file_info.reference_file' => false)
    study_files.each do |study_file|
      expression_label = study_file.ann_data_file_info.expression_axis_label
      next if expression_label.blank?

      study = study_file.study
      study.default_options[:expression_label] = expression_label
      study.save
    end
  end

  def self.down
  end
end
