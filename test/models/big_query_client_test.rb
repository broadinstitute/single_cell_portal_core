require "test_helper"

class BigQueryClientTest < ActiveSupport::TestCase

  test 'should instantiate client and assign attributes' do
    puts "#{File.basename(__FILE__)}: #{self.method_name}"
    @bq = BigQueryClient.new
    assert_not_nil @bq
    assert_not_nil @bq.client
    assert_equal @bq.project, ENV['GOOGLE_CLOUD_PROJECT']
    assert_equal @bq.service_account_credentials, ENV['SERVICE_ACCOUNT_KEY']
    puts "#{File.basename(__FILE__)}: #{self.method_name} completed!"
  end

end
