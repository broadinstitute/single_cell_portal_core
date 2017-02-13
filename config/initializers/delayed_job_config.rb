Delayed::Worker.destroy_failed_jobs = true
Delayed::Worker.max_attempts = 1
Delayed::Worker.max_run_time = 6.hours
Delayed::Worker.read_ahead = 10
Delayed::Worker.logger = Logger.new(File.join(Rails.root, 'log', 'delayed_job.log'))