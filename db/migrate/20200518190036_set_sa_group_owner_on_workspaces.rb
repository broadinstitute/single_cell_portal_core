# Backfilling permissions on existing workspaces not in the 'default' portal project by adding a
# Service Account owned user group to all workspaces
# This is in preparation of revoking all direct SA ownerships on workspaces

class SetSaGroupOwnerOnWorkspaces < Mongoid::Migration
  def self.up
    client = FireCloudClient.new
    ws_owner_group = AdminConfiguration.find_or_create_ws_user_group!
    Study.where(:firecloud_project.ne => FireCloudClient::PORTAL_NAMESPACE, detached: false).each do |study|
      # put in begin/rescue block in case there is a problem accessing the workspace, e.g. expired credits
      # all of these studies should already be marked as 'detached' but there could be some outliers
      begin
        puts "Updating workspace acl on #{study.firecloud_project}/#{study.firecloud_workspace}"
        acl = client.create_workspace_acl(ws_owner_group['groupEmail'], 'OWNER')
        client.update_workspace_acl(study.firecloud_project, study.firecloud_workspace, acl)
        puts "Update on #{study.firecloud_project}/#{study.firecloud_workspace} complete"
      rescue => e
        puts "Error updating workspace acl for #{study.firecloud_project}/#{study.firecloud_workspace}"
        context = ErrorTracker.format_extra_context(study, acl, ws_owner_group)
        ErrorTracker.report_exception(e, client.issuer, context)
      end
    end
  end

  def self.down
  end
end
