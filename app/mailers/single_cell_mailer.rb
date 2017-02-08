class SingleCellMailer < ApplicationMailer
  default from: 'no-reply@broadinstitute.org'

  def notify_user_parse_complete(email, title, message)
    @message = message
    mail(to: email, subject: title)
  end

  def notify_user_parse_fail(email, title, error)
    @error = error
    mail(to: email, subject: title)
  end

  def daily_disk_status
    @users = User.where(admin: true).map(&:email)
    header, portal_disk = `df -h /home/app/webapp`.split("\n")
    @table_header = header.split
    @portal_row = portal_disk.split
    @table_header.slice!(-1)
    @data_disk_row = `df -h /home/app/webapp/data`.split("\n").last.split
    mail(to: @users, subject: "Single Cell Portal Disk Usage for #{Date.today.to_s}") do |format|
      format.html
    end
  end
end
