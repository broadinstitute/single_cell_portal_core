require 'test_helper'

class MetricsServiceTest < ActiveSupport::TestCase

  before(:all) do
    @user = FactoryBot.create(:admin_user, test_array: @@users_to_clean)
    @user.update(registered_for_firecloud: true)
  end

  test 'should log to Mixpanel via Bard' do
    puts "#{File.basename(__FILE__)}: #{self.method_name}"

    event = "ingest"

    # As input into MetricsService.log from e.g. IngestJob.get_email_and_log_to_mixpanel
    input_props = {
      perfTime: 276322,
      fileType: "Cluster",
      fileSize: 680,
      action: "ingest_cluster",
      studyAccession: "SCP3",
      clusterType: "3d",
      numClusterPoints: 15,
      canSubsample: false,
      metadataFilePresent: false,
      logger:"app-backend"
    }

    # As passed from MetricsService.log to MetricsService.post_to_bard
    # Would be handy if we ever want to test that boundary.
    expected_output_props = input_props.merge({
      appId: "single-cell-portal",
      env: "test",
      authenticated: true,
      registeredForTerra: true,
      abTests: []
    })

    # As input into RestClient::Request.execute.
    # These expected arguments are the main thing we are testing.
    expected_args = {
      url: "https://terra-bard-dev.appspot.com/api/event",
      headers: {"Content-Type" => "application/json", 'Authorization' => "Bearer #{@user.token_for_api_call.dig(:access_token)}"},
      payload: {event: event, properties: expected_output_props}.to_json,
      method: "POST"
    }

    # Mock network traffic to/from Bard, the DSP service proxying Mixpanel
    mock = Minitest::Mock.new
    mock.expect :call, mock, [expected_args] # Mock `execute` call (request)

    RestClient::Request.stub :execute, mock do
      MetricsService.log(event, input_props, @user)
      mock.verify
    end

    puts "#{File.basename(__FILE__)}: #{self.method_name} successful!"
  end

  test 'should post expected data to Mixpanel `identify` endpoint' do
    puts "#{File.basename(__FILE__)}: #{self.method_name}"

    cookies = {
      user_id: '168d8f62-f813-4e45-61d7-b81afe29642a' # Random UUIDv4 string
    }.with_indifferent_access
    anon_id = cookies['user_id']

    # As input into RestClient::Request.execute.
    # These expected arguments are the main thing we are testing.
    expected_args = {
      url: "https://terra-bard-dev.appspot.com/api/identify",
      headers: {"Authorization" => "Bearer #{@user.token_for_api_call.dig(:access_token)}", "Content-Type" => "application/json"},
      payload: {anonId: anon_id}.to_json,
      method: "POST"
    }

    # Mock network traffic to/from Bard, the DSP service proxying Mixpanel
    mock = Minitest::Mock.new
    mock.expect :call, mock, [expected_args] # Mock `execute` call (request)

    RestClient::Request.stub :execute, mock do
      MetricsService.merge_identities_in_mixpanel(@user, cookies)
      mock.verify
    end

    puts "#{File.basename(__FILE__)}: #{self.method_name} successful!"
  end

  test 'should report errors to mixpanel' do
    puts "#{File.basename(__FILE__)}: #{self.method_name}"

    request_parameters = { 'controller' => 'site', 'action' => 'index' }
    fullpath = '/single_cell'
    user_id = SecureRandom.uuid
    user_agent = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML ' \
                 'like Gecko) Chrome/88.0.4324.96 Safari/537.36'
    # mock environment for request object (sets necessary values for MetricsService.report_error)
    env = {
      'rack.request.cookie_hash' => {
        user_id: user_id
      },
      'rack.input' => {},
      'action_dispatch.request.path_parameters' => request_parameters,
      'PATH_INFO' => fullpath,
      'HTTP_USER_AGENT' => user_agent
    }.with_indifferent_access

    request = ActionDispatch::Request.new(env)
    error = StandardError.new('this is the error message')
    browser = Browser.new(user_agent)

    expected_output_props = {
      appFullPath: fullpath,
      appPath: 'root',
      referrer: nil,
      type: error.class.name,
      text: error.message,
      appId: 'single-cell-portal',
      os: browser.platform.name,
      browser: browser.name,
      browser_version: browser.version,
      brand: nil,
      env: Rails.env,
      logger: 'app-backend',
      authenticated: false,
      distinct_id: user_id
    }.with_indifferent_access

    expected_args = {
      url: 'https://terra-bard-dev.appspot.com/api/event',
      headers: {'Content-Type' => 'application/json'},
      payload: {event: 'error', properties: expected_output_props}.to_json,
      method: 'POST'
    }

    mock = Minitest::Mock.new

    mock.expect :call, mock, [expected_args]

    RestClient::Request.stub :execute, mock do
      MetricsService.report_error(error, request)
      mock.verify
    end

    puts "#{File.basename(__FILE__)}: #{self.method_name} successful!"
  end

  # ensure study names are removed from urls
  test 'should sanitize input url' do
    puts "#{File.basename(__FILE__)}: #{self.method_name}"

    input_url = '/single_cell/study/SCP1/this-is-the-name'
    santized_url = MetricsService.sanitize_url(input_url)
    expected_url = '/single_cell/study/SCP1'
    assert_equal expected_url, santized_url

    # handle nil inputs
    assert_nil MetricsService.sanitize_url(nil)

    puts "#{File.basename(__FILE__)}: #{self.method_name} successful!"
  end

  test 'should get page name from params' do
    puts "#{File.basename(__FILE__)}: #{self.method_name}"

    controller_name = 'foo'
    action_name = 'bar'
    expected_output = [controller_name, action_name].join('-')
    page_name = MetricsService.get_page_name(controller_name, action_name)
    assert_equal expected_output, page_name

    # handle "root" case
    controller_name = 'site'
    action_name = 'index'
    expected_output = 'root'
    root_page_name = MetricsService.get_page_name(controller_name, action_name)
    assert_equal expected_output, root_page_name

    puts "#{File.basename(__FILE__)}: #{self.method_name} successful!"
  end

  # this test ensures that we configure auth headers correctly based on a user's Terra registration status
  # POSTs to Bard w/ users who are not registered that contain the Authorization: Bearer token will respond 503
  # and will not log activity, which leads to missing analytics in Mixpanel
  test 'should remove auth headers for non-Terra users' do
    puts "#{File.basename(__FILE__)}: #{self.method_name}"

    unregistered_user = FactoryBot.create(:admin_user, test_array: @@users_to_clean)
    unregistered_user.update(registered_for_firecloud: false, metrics_uuid: SecureRandom.uuid)

    event = 'fake-event'
    input_props = {
      foo: 'bar',
      bing: 'baz',
      logger: "app-backend"
    }

    expected_output_props = input_props.merge(
      {
        appId: "single-cell-portal",
        env: "test",
        authenticated: false,
        registeredForTerra: false,
        distinct_id: unregistered_user.metrics_uuid,
        abTests: []
      }
    )

    # As input into RestClient::Request.execute.
    # These expected arguments are the main thing we are testing.
    expected_args = {
      url: "https://terra-bard-dev.appspot.com/api/event",
      headers: {"Content-Type" => "application/json"},
      payload: {event: event, properties: expected_output_props}.to_json,
      method: "POST"
    }

    # Mock network traffic to/from Bard, the DSP service proxying Mixpanel
    mock = Minitest::Mock.new
    mock.expect :call, mock, [expected_args] # Mock `execute` call (request)
    RestClient::Request.stub :execute, mock do
      MetricsService.log(event, input_props, unregistered_user)
      mock.verify
    end

    puts "#{File.basename(__FILE__)}: #{self.method_name} successful!"
  end
end
