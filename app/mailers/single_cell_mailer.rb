class SingleCellMailer < ApplicationMailer

  ###
  #
  # Mailer that contains all portal-based emails to users & admins.
  #
  ###

  default from: 'no-reply@broadinstitute.org'
  BATCH_DELIVERY_SIZE = 500

  # deliver an email to a batch users (from SingleCellMailer.batch_users_email)
  def users_email(users, from, subject, message)
    @message = message
    mail(to: from, bcc: users, subject: "[Single Cell Portal Message] #{subject}", from: from) do |format|
      format.html {@message.html_safe}
    end
  end

  # deliver an email to all users
  def batch_users_email(email_params, user)
    users = email_params[:preview] == "1" ? [user.email] : User.where(admin_email_delivery: true).map(&:email)
    # send email in batches to sidestep Sendgrid API quotas
    users.each_slice(BATCH_DELIVERY_SIZE) do |email_batch|
      users_email(email_batch, email_params[:from], email_params[:subject], email_params[:contents]).deliver
    end
  end

  def notify_admin_upload_fail(study_file, error)
    @users = User.where(admin: true).map(&:email)
    @study = study_file.study
    @study_file = study_file
    @error = error
    mail(to: @users, subject: '[Single Cell Portal ERROR] FireCloud auto-upload fail in ' + @study.name) do |format|
      format.html
    end
  end

  # notify user of a failed upload that never parsed/pushed to bucket
  # will bcc dev team if configured
  def notify_user_upload_fail(study_file, study, user)
    @study_file = study_file
    @study = study
    dev_email_config = AdminConfiguration.find_by(config_type: 'QA Dev Email')
    dev_email = dev_email_config.present? ? dev_email_config.value : nil
    title = "#{study_file.upload_file_name} did not finish uploading"
    mail(to: user.email, bcc: dev_email, subject: '[Single Cell Portal Notifier] ' + title)
  end

  def notify_user_parse_complete(email, title, message, study)
    @message = message
    @study = study
    mail(to: email, subject: '[Single Cell Portal Notifier] ' + title)
  end

  def notify_user_parse_fail(email, title, error, study)
    @error = error
    @study = study
    mail(to: email, subject: '[Single Cell Portal Notifier] ' + title)
  end

  def notify_admin_parse_fail(user_email, title, contents)
    dev_email_config = AdminConfiguration.find_by(config_type: 'QA Dev Email')
    if dev_email_config.present?
      dev_email = dev_email_config.value
      @contents = contents
      @user_email = user_email
      mail(to: dev_email, subject: '[Single Cell Portal Admin Notification] ' + title)
    end
  end

  def daily_disk_status
    @users = User.where(admin: true).map(&:email)
    header, portal_disk = `df -h /home/app/webapp`.split("\n")
    @table_header = header.split
    @portal_row = portal_disk.split
    @table_header.slice!(-1)
    @data_disk_row = `df -h /home/app/webapp/data`.split("\n").last.split
    mail(to: @users, subject: "Single Cell Portal Disk Usage for #{Time.zone.today.to_s}") do |format|
      format.html
    end
  end

  def delayed_job_email(message)
    @users = User.where(admin: true).map(&:email)

    mail(to: @users, subject: 'Single Cell Portal DelayedJob workers automatically restarted',
         body: message,
         content_type: 'text/plain'
    )
  end

  def share_notification(user, share)
    @share = share
    @study = @share.study
    @user = user
    subject = "[Single Cell Portal Notifier] Study: #{@study.name} has been shared"

    if @study.deliver_emails? && @share.deliver_emails?
      mail(to: @share.email, cc: user.email, subject: subject) do |format|
        format.html
      end
    elsif !@study.deliver_emails? && @share.deliver_emails?
      mail(to: @share.email, subject: subject) do |format|
        format.html
      end
    elsif @study.deliver_emails? && !@share.deliver_emails?
      mail(to: user.email, subject: subject) do |format|
        format.html
      end
    else
      nil # neither user requested to be notified, so do nothing
    end
	end

  def share_annotation_notification(user, share)
    @share = share
    @user_annotation = @share.user_annotation
    @user = user

    mail(to: @share.email, cc: user.email, subject: "[Single Cell Portal Notifier] Annotation: #{@user_annotation.name} has been shared") do |format|
      format.html
    end
  end

  def share_update_notification(study, changes, update_user)
		@study = study
		@changes = changes
		@notify = @study.study_shares.where(deliver_emails: true).map(&:email)
    if @study.deliver_emails?
      @notify << @study.user.email
    end

		# remove user performing action from notification
		@notify.delete(update_user.email)
    unless @notify.empty?
      mail(to: @notify, subject: "[Single Cell Portal Notifier] Study: #{@study.name} has been updated") do |format|
        format.html
      end
    end
  end

  def annot_share_update_notification(annot, changes, update_user)
    @user_annotation = annot
    @changes = changes
    @notify = @user_annotation.user_annotation_shares.map(&:email)
    @notify << @user_annotation.user.email

    # remove user performing action from notification
    @notify.delete(update_user.email)
    mail(to: @notify, subject: "[Single Cell Portal Notifier] Annotation: #{@user_annotation.name} has been updated") do |format|
      format.html
    end
  end

	def share_delete_fail(study, share)
		@study = study
		@share = share
		@message = "<p>The study #{@study.name} was unable to properly revoke sharing to #{@share}</p>
								<p>Please log into <a href='https://app.terra.bio'>Terra</a> and manually remove this user</p>".html_safe
		if @study.deliver_emails?
      mail(to: @study.user.email, subject: "[Single Cell Portal Notifier] Study: #{@study.name} sharing update failed") do |format|
        format.html {render html: @message}
      end
    end
	end

	def study_delete_notification(study, user)
		@study = study
		@user = user.email

		@notify = @study.study_shares.where(deliver_emails: true).map(&:email)
    if @study.deliver_emails?
      @notify << @study.user.email
    end
		@notify.delete_if(&:blank?)

    unless @notify.empty?
      mail(to: @notify, subject: "[Single Cell Portal Notifier] Study: #{@study.name} has been deleted") do |format|
        format.html {render html: "<p>The study #{@study.name} has been deleted by #{@user}</p>".html_safe}
      end
    end
  end

  def annotation_publish_fail(annot, user, error)
    @user_annotation = annot
    @user = user.email
    @error = error

    mail(@user, subject:  "[Single Cell Portal Notifier] User Annotation: #{@user_annotation.name} failed to publish") do |format|
      format.html
    end
  end

  def annotation_delete_notification(annot, user)
    @user_annotation = annot
    @user = user.email

    @notify = @user_annotation.user_annotation_shares.map(&:email)
    @notify << @user_annotation.user.email
    @notify.delete_if(&:blank?)

    mail(to: @notify, subject: "[Single Cell Portal Notifier] User Annotation: #{@user_annotation.name} has been deleted") do |format|
      format.html {render html: "<p>The annotation #{@user_annotation.name} has been deleted by #{@user}</p>".html_safe}
    end
  end

  # notify a user of a missing download file
  def user_download_fail_notification(study, file)
    @study = study
    @file_location = file
    if @study.deliver_emails?
      mail(to: @study.user.email, subject: "[Single Cell Portal Notifier] A file is missing from your study") do |format|
        format.html
      end
    end
  end

  # generic admin notification email method
  def admin_notification(subject, requester, message)
    # don't deliver if config value is set to true
    unless Rails.application.config.disable_admin_notifications == true
      @subject = subject
      @requester = requester.nil? ? 'no-reply@broadinstitute.org' : requester
      @message = message
      @admins = User.where(admin: true).map(&:email)

      unless @admins.empty?
        mail(to: @admins, reply_to: @requester, subject: "[Single Cell Portal Admin Notification #{Rails.env != 'production' ? " (#{Rails.env})" : nil}]: #{@subject}") do |format|
          format.html
        end
      end
    end
  end

  # notifier of FireCloud API service interruptions
  def firecloud_api_notification(current_status, requester=nil)
    unless Rails.application.config.disable_admin_notifications == true
      @admins = User.where(admin: true).map(&:email)
      @requester = requester.nil? ? 'no-reply@broadinstitute.org' : requester
      @current_status = current_status
      unless @admins.empty?
        mail(to: @admins, reply_to: @requester, subject: "[Single Cell Portal Admin Notification #{Rails.env != 'production' ? " (#{Rails.env})" : nil}]: ALERT: FIRECLOUD API SERVICE INTERRUPTION") do |format|
          format.html
        end
      end
    end
  end

  # generic user notification
  def user_notification(user, subject, message)
    @subject = subject
    @message = message
    @user = user
    mail(to: @user.email, subject: "[Single Cell Portal Notifier]: #{subject}") do |format|
      format.html {render html: @message.html_safe}
    end
  end

  # nightly sanity check email looking for missing files
  def sanity_check(missing_files)
    @missing_files = missing_files
    @admins = User.where(admin: true).map(&:email)

    mail(to: @admins, subject: "[Single Cell Portal Admin Notification #{Rails.env != 'production' ? " (#{Rails.env})" : nil}]: Sanity check results: #{@missing_files.size} files missing") do |format|
      format.html
    end
  end

  # collect usage statistics for the given day and email admins
  def nightly_admin_report
    @admins = User.where(admin: true).map(&:email)
    @today = Time.zone.today
    @two_weeks_ago = @today - 2.weeks

    # get user, submission, and study stats
    @user_stats = SummaryStatsUtils.daily_total_and_active_user_counts
    @submissions = SummaryStatsUtils.analysis_submission_count
    @studies_created = SummaryStatsUtils.daily_study_creation_count

    # get number of ingest runs for the day
    @ingest_runs = SummaryStatsUtils.ingest_run_count

    # disk usage
    @disk_stats = SummaryStatsUtils.disk_usage

    # storage sanity check
    @missing_files = SummaryStatsUtils.storage_sanity_check

    mail(to: @admins, subject: "[Single Cell Portal Admin Notification#{Rails.env != 'production' ? " (#{Rails.env})" : nil}]: Nightly Server Report for #{@today}") do |format|
      format.html { render layout: 'nightly_admin_report' }
    end
  end
end
