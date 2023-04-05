class MarkAnnDataReferenceFiles < Mongoid::Migration
  def self.up
    StudyFile.where(file_type: 'AnnData').each do |study_file|
      # the IngestJob#set_anndata_file_info method handles initializing ann_data_file_info documents and checking for
      # parsed data and as such makes a convenient proxy for determining whether an AnnData file is 'reference' or not
      # Mongo queries don't honor 'default' values until they've been persisted to the document, hence this migration
      study = study_file.study
      job = IngestJob.new(study:, study_file:)
      job.set_anndata_file_info
      study_file.reload
      info = study_file.ann_data_file_info
      unless info.has_clusters? || info.has_metadata? || info.has_expression?
        study_file.ann_data_file_info.reference_file = true
        study_file.save
      end
    end
  end

  def self.down
  end
end
