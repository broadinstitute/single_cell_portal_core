# Service to record events to Mixpanel via Bard
#
# Mixpanel is a business analytics service for tracking user interactions.
# Bard is a DSP service that mediates writes to Mixpanel.
#
# Most logging to Mixpanel is done in JavaScript; see metrics-api.js and
# scp-api-metrics.js in /app/javascript/lib/.  But some logging is done
# in Rails to make it easy to analyze metrics around long-running events
# triggered by user interactions -- like upload and ingest -- or special
# identity resolution.

class MetricsService

  BARD_ROOT = Rails.application.config.bard_host_url

  def self.post_to_bard(params, user)
    params.merge!({
      method: 'POST'
    })
    begin
      Rails.logger.info "#{Time.zone.now}: Posting to Mixpanel. Params: #{params}"
      # Uncomment line below to get known-good test data
      # puts "Posting to Mixpanel.  Params: #{params}"
      RestClient::Request.execute(params)
    rescue RestClient::Exception => e
      # log error, unless this is CI, in which case we don't care
      Rails.logger.error "#{Time.zone.now}: Bard error in call to #{params[:url]}: #{e.message}" unless ENV['CI']
      # Rails.logger.error e.to_yaml
      if e.http_code != 503
        # TODO (SCP-2632): Refine handling of Bard "503 Service Unavailable" errors
        ErrorTracker.report_exception(e, user, params) unless ENV['CI']
      end
    end
  end

  def self.get_default_headers(user)
    headers = { 'Content-Type' => 'application/json'}
    if user.present? && user.registered_for_firecloud && user.token_for_api_call.present?
      access_token = user.token_for_api_call
      headers.merge!({
        'Authorization' => "Bearer #{access_token.dig(:access_token)}",
      })
    end
    headers
  end

  # Merges unauth’d and auth’d user identities in Mixpanel via Bard
  #
  # To enable tracking users when they are signed in and not, Bard provides an
  # endpoint `/api/identify` to merge identities.  In SCP's case, the
  # anonynmous ID (`anonId`) is a random UUIDv4 string set as a cookie for all
  # users -- auth'd or not -- upon visiting SCP.

  # This call links that anonId to the user's bearer token used by DSP's Sam
  # service.  That bearer token is in turn linked to a deidentified
  # "distinct ID" used to track users across auth states in Mixpanel.
  def self.merge_identities_in_mixpanel(user, cookies={})

    Rails.logger.info "#{Time.zone.now}: Merging user identity in Mixpanel via Bard"

    headers = get_default_headers(user)

    # store random UUIDv4 string from client in user model to allow tracking API calls
    if cookies.key?('user_id')
      user_id = cookies['user_id']
    else
      user_id = user.get_metrics_uuid
    end

    # update metrics UUID if it has changed
    # this unifies browser cookie value with metrics_uuid to avoid double-counting users
    user.update(metrics_uuid: user_id) if user_id != user.metrics_uuid

    post_body = {
      'anonId' => user_id
    }.to_json

    params = {
      url: BARD_ROOT + '/api/identify',
      headers: headers,
      payload: post_body
    }

    # only post to /identify if user is registered, otherwise Bard responds 503 due to upstream errors in SAM
    self.post_to_bard(params, user) if user.registered_for_firecloud
  end

  # Log metrics to Mixpanel via Bard web service
  #
  # Bard docs:
  # https://terra-bard-prod.appspot.com/docs/
  #
  # @param {String} name Name of the event
  # @param {Hash} props Properties associated with the event
  # @param {User} user User model object
  def self.log(name, props={}, user=nil, request: nil)
    Rails.logger.info "#{Time.zone.now}: Logging analytics to Mixpanel for event name: #{name}"

    props.merge!({
      appId: 'single-cell-portal',
      env: Rails.env,
      logger: 'app-backend'
    })

    headers = get_default_headers(user)
    distinct_id = user&.get_metrics_uuid || request&.cookies&.[]('user_id')

    # configure properties/headers depending on user presence
    # only pass user token if user is registered for Terra to avoid 4xx/5xx errors
    if user.present? && user.registered_for_firecloud
      props.merge!({ authenticated: true, registeredForTerra: user.registered_for_firecloud })
    else
      props.merge!({ authenticated: false, registeredForTerra: false, distinct_id: })
    end

    # global tracking of A/B feature test groups
    props.merge!({ abTests: AbTest.load_assignments(distinct_id) })

    post_body = {'event' => name, 'properties' => props}.to_json

    params = {
      url: BARD_ROOT + '/api/event',
      headers: headers,
      payload: post_body
    }

    self.post_to_bard(params, user)
  end

  # Log error metrics to Mixpanel via Bard web service
  # Handled from rescue_from blocks in controllers
  #
  # Bard docs:
  # https://terra-bard-prod.appspot.com/docs/
  #
  # @param {Exception} exception - instance of exception that was caught
  # @param {ActionDispatch::Request} request - request object in which exception was thrown
  # @param {User} user - User model object, if present
  # @param {Study} study - Study model object, if present
  def self.report_error(exception, request, user=nil, study=nil)
    Rails.logger.error "Reporting error analytics to mixpanel for (#{exception.class.name}) #{exception.message}"

    # get browser/client information from user agent
    browser = Browser.new(request.env['HTTP_USER_AGENT'])

    # error properties hash details
    #
    # appFullPath: request URL where error occurred
    # appPath: Rails controller & method that corresponds to the error
    # type: error Ruby class
    # text: error message/details
    # appId: identifier for Single Cell Portal
    # env: Rails environment
    # studyAccession: corresponding SCP study (if present)
    # authenticated: user auth status
    # registeredForTerra: status of user Terra registration (if present)
    # distinct_id: user metrics UUID for identifying users in Bard
    # browser: client browser name
    # browser_version: client browser version
    # os: client operating system
    # logger: identifer that this event comes from the applications backend
    props = {
      appFullPath: self.sanitize_url(request.fullpath),
      appPath: self.get_page_name(request.parameters['controller'], request.parameters['action']),
      referrer: self.sanitize_url(request.referrer),
      type: exception.class.name,
      text: exception.message,
      appId: 'single-cell-portal',
      os: browser.platform.name,
      browser: browser.name,
      browser_version: browser.version,
      brand: request.query_parameters.dig('scpbr'),
      env: Rails.env,
      logger: 'app-backend'
    }

    # add study accession if this action was study-specific
    if study.present?
      props.merge!({studyAccession: study.accession})
    end

    headers = get_default_headers(user)

    # configure properties/headers depending on user presence
    # only pass user token if user is registered for Terra to avoid 4xx/5xx errors
    if user.present? && user.registered_for_firecloud
      props.merge!({ authenticated: true, registeredForTerra: user.registered_for_firecloud })
    else
      props.merge!({ authenticated: user.present?, distinct_id: request.cookies['user_id'] })
    end

    post_body = {'event' => 'error', 'properties' => props}.to_json

    params = {
      url: BARD_ROOT + '/api/event',
      headers: headers,
      payload: post_body
    }

    self.post_to_bard(params, user)
  end

  # remove study names from url, if present
  #
  # @param {String} url - input URL from SCP
  def self.sanitize_url(url)
    return nil if url.nil? # error handling for nil entry, e.g. request.referrer is not set
    study_name_match = url.match(/\/single_cell\/study\/SCP\d+/)
    if study_name_match.present?
      study_name_match.to_s
    else
      url
    end
  end

  # get a formatted identifer for controller/action
  #
  # @param {String} controller - name of Rails controller
  # @param {String} action - name of Rails action from controller
  def self.get_page_name(controller, action)
    page_name = "#{controller}-#{action}".gsub('_', '-')
    if page_name == 'site-index'
      page_name = 'root'
    end
    page_name
  end
end
