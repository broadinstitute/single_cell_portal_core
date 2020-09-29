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
      Rails.logger.info "#{Time.zone.now}: Posting to Mixpanel.  Params: #{params}"
      # Uncomment line below to get known-good test data
      # puts "Posting to Mixpanel.  Params: #{params}"
      RestClient::Request.execute(params)
    rescue RestClient::Exception => e
      Rails.logger.error "#{Time.zone.now}: Bard error in call to #{params[:url]}: #{e.message}"
      # Rails.logger.error e.to_yaml
      if e.http_code != 503
        # TODO (SCP-2632): Refine handling of Bard "503 Service Unavailable" errors
        ErrorTracker.report_exception(e, user, params)
      end
    end
  end

  def self.get_default_headers(user)
    access_token = user.token_for_api_call
    {
      'Authorization': "Bearer #{access_token.present? ? access_token.dig('access_token') : nil }",
      'Content-Type': 'application/json'
    }
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
      'anonId': user_id
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
  def self.log(name, props={}, user)
    Rails.logger.info "#{Time.zone.now}: Logging analytics to Mixpanel for event name: #{name}"

    props.merge!({
      appId: 'single-cell-portal',
      env: Rails.env,
      registeredForTerra: user.registered_for_firecloud
    })

    headers = get_default_headers(user)

    access_token = user.token_for_api_call
    user_id = user.get_metrics_uuid

    if access_token.nil? || !user.registered_for_firecloud
      # User is unauthenticated / unregistered / anonymous
      props['distinct_id'] = user_id
      headers.delete('Authorization')
      props['authenticated'] = false
    else
      props['authenticated'] = true
    end

    post_body = {'event': name, 'properties': props}.to_json

    params = {
      url: BARD_ROOT + '/api/event',
      headers: headers,
      payload: post_body
    }

    self.post_to_bard(params, user)

  end
end
