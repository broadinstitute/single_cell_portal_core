require 'json'

# Run the rails server in non-dockerized form
# usage:
# ruby rails_local_setup.rb <username>
# you may also specify --no-tcell to run locally without tcell, which currently clutters the console with CSP warnings in development mode

if ARGV[0].nil?
  puts 'You must specify your username'
  exit
end

exclude_tcell = ARGV.include?('--no-tcell')

username = ARGV[0]
source_file_string = "#!/bin/bash\n"
source_file_string += "export NOT_DOCKERIZED=true\n"
source_file_string += "export HOSTNAME=localhost\n"

base_vault_path = "secret/kdux/scp/development/#{username}"
vault_secret_path = "#{base_vault_path}/scp_config.json"
read_only_service_account_path = "#{base_vault_path}/read_only_service_account.json"
service_account_path = "#{base_vault_path}/scp_service_account.json"

# defaults
PASSENGER_APP_ENV = "development"
CONFIG_DIR = "config"

  # load raw secrets from vault
puts 'Processing secret parameters from vault'
secret_string = `vault read -format=json #{vault_secret_path}`
secret_data_hash = JSON.parse(secret_string)['data']

secret_data_hash.each do |key, value|
  # if tcell is excluded, set the related environment variables to empty -- this means tcell will not be active
  if exclude_tcell && key.include?('TCELL')
    source_file_string += "export #{key}=\n"
  else
    source_file_string += "export #{key}=#{value}\n"
  end
end

puts 'Processing service account info'
service_account_string = `vault read -format=json #{service_account_path}`
service_account_hash = JSON.parse(service_account_string)['data']

File.open("#{CONFIG_DIR}/.scp_service_account.json", 'w') { |file| file.write(service_account_hash.to_json) }
puts "Setting google cloud project: #{service_account_hash['project_id']}"
source_file_string += "export GOOGLE_CLOUD_PROJECT=#{service_account_hash['project_id']}\n"
source_file_string += "export SERVICE_ACCOUNT_KEY=#{CONFIG_DIR}/.scp_service_account.json\n"

puts 'Processing readonly service account info'
readonly_string = `vault read -format=json #{read_only_service_account_path}`
readonly_hash = JSON.parse(service_account_string)['data']
File.open("#{CONFIG_DIR}/.read_only_service_account.json", 'w') { |file| file.write(readonly_hash.to_json) }
source_file_string += "export READ_ONLY_SERVICE_ACCOUNT_KEY=#{CONFIG_DIR}/.read_only_service_account.json\n"

puts 'Setting secret_key_base'
source_file_string += "export SECRET_KEY_BASE=#{`openssl rand -hex 64`}\n"

if !exclude_tcell
  puts 'Configuring TCell'
  `bin/configure_tcell.rb`
else
  puts "****\nYou are developing with TCell disabled--be sure to test that any third-party scripts or connection sources you add are also added to TCell\n****\n"
end

File.open("#{CONFIG_DIR}/secrets/.source_env.bash", 'w') { |file| file.write(source_file_string) }

puts "Load Complete!\n  Run the command below to load the environment variables you need into your shell\n\nsource config/secrets/.source_env.bash\n\n"
