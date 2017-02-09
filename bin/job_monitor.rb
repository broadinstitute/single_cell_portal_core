#! /usr/bin/env ruby

require 'net/smtp'

WEB_DIR = File.expand_path(File.join(File.dirname(__FILE__), '..'))
Dir.chdir(WEB_DIR)

# set up defaults
@env = 'production'
@num_workers = 4
@interactive = false

# parse args
ARGV.each do |arg|
	arg =~ /\-e\=/ ? @env = arg.gsub(/\-e\=/, "") : nil
	arg =~ /\-n\=/ ? @num_workers = arg.gsub(/\-p\=/, "") : nil
	arg =~ /\-i/ ? @interactive = true : false
end

@from_email = 'no-reply@broadinstitute.org'
@to_email = 'bistline@broadinstitute.org'

# get current delayed_job processes & pids from files
processes = `ps aux | grep delayed_job`.split("\n").map {|l| l.split}.map {|l| [l[1], l.last]}.keep_if {|l| l.last.include?('.')}
pid_files = Dir.entries(File.join(WEB_DIR, 'tmp','pids')).delete_if {|p| p.start_with?('.')}
pids = {}
pid_files.each do |file|
	pids[file.chomp('.pid')] = File.open(File.join(WEB_DIR, 'tmp', 'pids', file)).read.strip
end

# check to make sure all delayed_job daemons are still running
@running = true
if pids.size != processes.size
	@running = false
else
	pids.each do |command, pid|
		if processes.include?([pid, command])
			next
		else
			@running = false
			puts "#{command} has died, does not match pid: #{pid}"
			break
		end
	end
end

# checks to see if any workers have been killed
@date = Time.now.strftime("%Y-%m-%d %H:%M:%S")
if @running == false
	@log_message = "#{@date}: One or more delayed_job workers have died.  Restarting daemon.\n"

	# restart delayed job workers
	system("sudo -E -u app -H bin/delayed_job restart #{@env} -n #{@num_workers}")

	# send email to admin
	Net::SMTP.start('smtp.sendgrid.net', 2525, ENV['SENDGRID_USERNAME'], ENV['SENDGRID_PASSWORD'], :plain) do |smtp|
		smtp.open_message_stream(@from_email, @to_email) do |contents|
			contents.puts "From: #{@from_email}"
			contents.puts "To: #{@to_email}"
			contents.puts "Content-Type: text/html; charset=utf-8"
			contents.puts "Subject: Single Cell DelayedJob workers died as of #{@date}"
			contents.puts ""
			contents.puts "#{@log_message.gsub(/\n/, '<br />')}"
		end
	end
elsif @interactive && @running
	puts "All jobs are running normally in #{@env}"
	processes.each do |pid, command|
		puts "#{pid}: #{command}"
	end
end