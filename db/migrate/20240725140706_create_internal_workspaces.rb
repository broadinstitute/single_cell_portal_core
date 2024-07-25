class CreateInternalWorkspaces < Mongoid::Migration
  def self.up
    accessions = Study.where(queued_for_deletion: false, detached: false).pluck(:accession)
    accessions.each do |accession|
      study = Study.find_by(accession:)
      study.delay.add_internal_workspace # run in background so as not to be blocking on deployment
    end
  end

  # rollback doesn't need to be non-blocking
  def self.down
    assigned = Study.where(queued_for_deletion: false, detached: false, :internal_workspace.nin => [nil, ''])
    workspaces = assigned.pluck(:internal_workspace)
    client = ApplicationController.firecloud_client
    project = FireCloudClient::PORTAL_NAMESPACE
    workspaces.each do |workspace|
      begin
        client.delete_workspace(project, workspace)
      rescue RestClient::Exception => e
        Rails.logger.error "error deleting #{workspace}: #{e.message}"
      end
    end
    assigned.update_all(internal_workspace: nil, internal_bucket_id: nil)
  end
end
