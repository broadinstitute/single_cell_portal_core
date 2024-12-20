Delayed::Worker.destroy_failed_jobs = true
Delayed::Worker.max_attempts = 1
Delayed::Worker.max_run_time = 24.hours
Delayed::Worker.read_ahead = 10
Delayed::Worker.logger = Logger.new(File.join(Rails.root, 'log', "delayed_job.#{Rails.env}.log"))
Delayed::Worker.default_queue_name = :default

if Rails.env.test? || Rails.env.development? # save a little time in testing/dev
  Delayed::Worker.sleep_delay = 5 # seconds
end
