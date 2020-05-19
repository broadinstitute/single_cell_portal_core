module ErrorTracker

  # capture and report an exception to Sentry via Raven, setting user context & params as needed
  def self.report_exception(exception, user, extra_context={})
    # only report to Sentry if configured and not in dev or test environment
    if %w(development test).include?(Rails.env) || ENV['SENTRY_DSN'].nil?
      Rails.logger.error "Suppressing error reporting to Sentry: #{exception.class.name}:#{exception.message}"
    else
      Raven.capture_exception(exception, user: {identifer: extract_user_identifier(user)}, extra: extra_context)
    end
  end

  # generate a Hash of extra context based on types of objects sent
  def self.format_extra_context(*objects)
    context = {}
    objects.each do |object|
      if object.is_a?(Hash)
        context.merge!(object)
      elsif object.respond_to?(:attributes)
        context[object.class.name.underscore] = object.attributes.to_h
      end
    end
    context
  end

  def self.extract_user_identifier(user)
    if user.is_a?(User)
      user.id.to_s
    else
      user
    end
  end
end
