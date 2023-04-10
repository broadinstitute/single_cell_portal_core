#!/usr/bin/env ruby

require 'json'
require 'optparse'

# Set up the environment for doing local development/testing outside of Docker
# will export all secrets from vault for the current user and create configuration files
# can also be run to print 'dockerized' paths to use inside of Docker for hybrid setup
#
# usage: ./rails_local_setup.rb [-e, --environment ENVIRONMENT] [-u, --username USERNAME] [-d, --docker-paths]

# defaults
username = `whoami`.chomp
environment = 'development'
output_dir = "#{File.expand_path('.')}/config"

# options parsing
OptionParser.new do |opts|
  opts.banner = "rails_local_setup.rb: Set up the environment for doing local development/testing outside of Docker.\n" \
                "Usage: ruby rails_local_setup.rb [-e, --environment ENVIRONMENT] [-u, --username USERNAME]:\n\nARGUMENTS:"

  opts.on("-u", "--username USERNAME", String, "Username for exporting vault secrets, defaults to #{username} on this machine") do |u|
    username = u.strip
    puts "USERNAME: #{username}"
  end

  opts.on("-e", "--environment ENVIRONMENT", String, "Set the rails environment (defaults to #{environment})") do |e|
    environment = e.strip
    puts "ENVIRONMENT: #{environment}"
  end

  opts.on('-d', '--docker-paths', 'Use Dockerized paths for configurations (for running inside Docker)') do |d|
    output_dir = '/home/app/webapp/config'
  end

  opts.on("-h", "--help", "Prints this help") do
    puts "\n#{opts}\n"
    exit
  end

end.parse!

source_file_string = "#!/bin/bash\n"
source_file_string += "export NOT_DOCKERIZED=true\n"
source_file_string += "export HOSTNAME=localhost\n"

base_vault_path = "secret/kdux/scp/development/#{username}"
vault_secret_path = "#{base_vault_path}/scp_config.json"
read_only_service_account_path = "#{base_vault_path}/read_only_service_account.json"
service_account_path = "#{base_vault_path}/scp_service_account.json"
mongo_user_path = "#{base_vault_path}/mongo/user"

# defaults
PASSENGER_APP_ENV = environment
CONFIG_DIR = File.expand_path('.') + "/config"


  # load raw secrets from vault
puts 'Processing secret parameters from Vault'
secret_string = `vault read -format=json #{vault_secret_path}`
secret_data_hash = JSON.parse(secret_string)['data']

secret_data_hash.each do |key, value|
  source_file_string += "export #{key}=#{value}\n"
end

mongo_user_string = `vault read -format=json #{mongo_user_path}`
mongo_user_hash = JSON.parse(mongo_user_string)['data']

source_file_string += "export DATABASE_NAME=single_cell_portal_development\n"
source_file_string += "export MONGODB_USERNAME=#{mongo_user_hash['username']}\n"
source_file_string += "export MONGODB_PASSWORD=#{mongo_user_hash['password']}\n"
source_file_string += "export DATABASE_HOST=#{secret_data_hash['MONGO_LOCALHOST']}\n"

puts 'Processing service account info'
service_account_string = `vault read -format=json #{service_account_path}`
service_account_hash = JSON.parse(service_account_string)['data']

File.open("#{CONFIG_DIR}/.scp_service_account.json", 'w') { |file| file.write(service_account_hash.to_json) }
puts "Setting google cloud project: #{service_account_hash['project_id']}"
source_file_string += "export GOOGLE_CLOUD_PROJECT=#{service_account_hash['project_id']}\n"
source_file_string += "export SERVICE_ACCOUNT_KEY=#{output_dir}/.scp_service_account.json\n"

puts 'Processing readonly service account info'
readonly_string = `vault read -format=json #{read_only_service_account_path}`
readonly_hash = JSON.parse(readonly_string)['data']
File.open("#{CONFIG_DIR}/.read_only_service_account.json", 'w') { |file| file.write(readonly_hash.to_json) }
source_file_string += "export READ_ONLY_SERVICE_ACCOUNT_KEY=#{output_dir}/.read_only_service_account.json\n"

File.open("#{CONFIG_DIR}/secrets/.source_env.bash", 'w') { |file| file.write(source_file_string) }

puts "Load Complete!\n  Run the command below to load the environment variables you need into your shell\n\nsource config/secrets/.source_env.bash\n\n"
