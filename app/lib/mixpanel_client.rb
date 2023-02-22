# handles connecting to Mixpanel api

class MixpanelClient
  def self.authorization_string
    mixpanel_secret = ENV['MIXPANEL_SECRET']
    service_account_name = Rails.configuration.mixpanel_service_account
    "Basic #{service_account_name}:#{mixpanel_secret}"
  end

  def self.project_id
    Rails.configuration.mixpanel_project_id
  end

  # see https://developer.mixpanel.com/reference/segmentation-query
  def self.fetch_segmentation_query(
    event = nil,
    type = 'unique',
    where_string = '',
    from_date = '2020-10-01'.to_date,
    to_date = Date.today,
    unit = 'month',
    on_string = ''
  )

    request = {
      method: 'GET',
      headers: {
        'Accept': 'application/json',
        'Authorization': authorization_string,
        params: {
          event: event,
          project_id: project_id,
          from_date: from_date.to_s,
          to_date: to_date.to_s,
          unit: unit,
          type: type,
          where: where_string,
          on: on_string
        }
      },
      url: "https://mixpanel.com/api/2.0/segmentation"
    }

    response = RestClient::Request.execute(request)
    result = JSON.parse(response.body)
    if on_string.empty?
      # simplify the response so that the consumer doesn't have to dig by the event name
      result['data']['values'] = result['data']['values'][event]
    end
    result
  end

end