module Loggable
  extend ActiveSupport::Concern

  # shortcut to log to STDOUT and Rails log simultaneously
  def log_message(message, level: :info)
    puts message
    Rails.logger.send(level, message)
  end
end
