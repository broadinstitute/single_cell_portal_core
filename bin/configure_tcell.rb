#! /usr/bin/env ruby
#
# create tcell_agent.config files if enabled in enviroment

require 'json'

unless ENV['TCELL_AGENT_APP_ID'].nil? || ENV['TCELL_AGENT_API_KEY'].nil?

  tcell_config_json = {
      version: 1,
      applications: [
          {
              app_id: "#{ENV['TCELL_AGENT_APP_ID']}",
              api_key: "#{ENV['TCELL_AGENT_API_KEY']}",
              tcell_api_url: "https://us.agent.tcell.insight.rapid7.com/api/v1",
              tcell_input_url: "https://us.input.tcell.insight.rapid7.com/api/v1",
              js_agent_api_base_url: "https://us.agent.tcell.insight.rapid7.com/api/v1"
          }
      ]
  }

  app_root_path = ENV['NOT_DOCKERIZED'] ? '.' : '/home/app/webapp/'
  tcell_config_file = File.new("#{app_root_path}/config/tcell_agent.config", 'w+')
  tcell_config_file.write(tcell_config_json.to_json)
  tcell_config_file.close

end
