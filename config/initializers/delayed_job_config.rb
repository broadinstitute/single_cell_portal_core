Delayed::Worker.destroy_failed_jobs = true
Delayed::Worker.max_attempts = 1
Delayed::Worker.max_run_time = 24.hours
Delayed::Worker.read_ahead = 10
Delayed::Worker.logger = Logger.new(File.join(Rails.root, 'log', "delayed_job.#{Rails.env}.log"))
Delayed::Worker.default_queue_name = :default

if Rails.env.test? || Rails.env.development? # save a little time in testing/dev
  Delayed::Worker.sleep_delay = 5 # seconds
end

# log errors from Delayed::Job to STDOUT
if Rails.env.test?
  Delayed::Worker.logger = ActiveSupport::Logger.new(STDOUT)
  Delayed::Worker.logger.level = Logger::ERROR
end

# Fixing class loader issues with delayed_job, for Rails 5
# from https://stackoverflow.com/questions/4705867/rails-doesnt-load-classes-on-deserializing-yaml-marshal-objects
module Psych::Visitors
  ToRuby.class_eval do
    def resolve_class(klassname)
      begin
        class_loader.load klassname
      rescue ArgumentError
        require_dependency klassname.underscore
        klassname.constantize
      end
    end
  end
end
