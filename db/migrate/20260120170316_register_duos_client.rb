class RegisterDuosClient < Mongoid::Migration
  def self.up
    client = DuosClient.new
    client.register unless client.registered?
    registration = client.registration
    puts "#{registration['email']} is registered as user:#{registration['userId']} with roles: " \
           "#{registration['roles'].map {|r| r['name']}.join(',')}"
    client.accept_tos unless client.tos_accepted?
  end

  def self.down ; end
end
