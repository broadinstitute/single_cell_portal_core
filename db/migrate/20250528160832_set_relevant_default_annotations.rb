class SetRelevantDefaultAnnotations < Mongoid::Migration
  def self.up
    accessions = Study.where(queued_for_deletion: false).pluck(:accession)
    accessions.each do |accession|
      study = Study.find_by(accession:)
      begin
        ClusterCacheService.configure_default_annotation(study)
      rescue => e
        ErrorTracker.report_exception(e, nil,{ study: })
      end
    end
  end

  def self.down
    # default annotations can be reset manually if needed
  end
end
