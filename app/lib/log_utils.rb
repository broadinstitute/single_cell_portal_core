class LogUtils
  # quick-and-dirty display of HH:MM:SS time.  Replacement for time_difference gem
  # which does not support rails 6
  def time_diff(start_time, end_time)
    seconds_diff = (start_time - end_time).to_i.abs

    hours = seconds_diff / 3600
    seconds_diff -= hours * 3600

    minutes = seconds_diff / 60
    seconds_diff -= minutes * 60

    seconds = seconds_diff

    '%02d:%02d:%02d' % [hours, minutes, seconds]
  end
end
