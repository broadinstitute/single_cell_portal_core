module Loggable
  extend ActiveSupport::Concern

  # shortcut to log to STDOUT and Rails log simultaneously
  def log_message(message)
    puts message
    Rails.logger.info message
  end
end
