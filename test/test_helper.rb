require 'simplecov_helper'
require 'rest_client_helper'

ENV["RAILS_ENV"] = "test"
require File.expand_path("../../config/environment", __FILE__)
require "rails/test_help"
require "minitest/rails"
require "minitest/autorun"

# To add Capybara feature tests add `gem "minitest-rails-capybara"`
# to the test group in the Gemfile and uncomment the following:
# require "minitest/rails/capybara"

# Uncomment for awesome colorful output
require "minitest/pride"

# Include in a test class to get start/stop messages to standard out including suite and test timings
# messages will be written to stdout of the format
#
# SUITE ExploreControllerTest starting
# explore_controller_test.rb:72 test_should_handle_invalid_study_id starting
# explore_controller_test.rb:72 test_should_handle_invalid_study_id completed (0.925 sec)
# .explore_controller_test.rb:78 test_should_enforce_view_privileges starting
# explore_controller_test.rb:78 test_should_enforce_view_privileges completed (2.249 sec)
# .SUITE ExploreControllerTest completed (14.294 sec)
module TestInstrumentor
  include Minitest::Hooks

  around do |&test_block|
    method_source = self.class.instance_method(self.method_name).source_location
    filename = File.basename(method_source[0])
    puts "#{filename}:#{method_source[1]} #{self.method_name} starting"
    bench = Benchmark.measure { super(&test_block) }
    puts "#{filename}:#{method_source[1]} #{self.method_name} completed (#{bench.real.round(3)} sec)"
  end

  around(:all) do |&test_suite|
    puts "SUITE #{self.class} starting"
    bench = Benchmark.measure { super(&test_suite) }
    puts "SUITE #{self.class} completed (#{bench.real.round(3)} sec)"
  end
end


# inlcude this module in tests for easy cleaning of created users/studies
# specify @@studies_to_clean or @@users_to_clean as the test_array of any
# calls to the respective factories.
# this allows studies to be created in individual tests, but cleanup to be assured
# even if the test fails partway through.
module SelfCleaningSuite
  include Minitest::Hooks

  # note that these need to be @@ class variables, since the test instance does
  # not exist in the after(:all) hook
  @@studies_to_clean = []
  @@users_to_clean = []

  after(:all) do
    puts "#{self.class}: Cleaning up #{@@studies_to_clean.count} studies, #{@@users_to_clean.count} users"
    [@@studies_to_clean, @@users_to_clean].each do |entity_list|
      entity_list.each do |entity|
        if entity.is_a?(Study) && !entity.detached?
          # non-detached studies will leave behind workspaces if not removed
          entity.destroy_and_remove_workspace
        else
          entity.destroy
        end
      end
      entity_list.clear
    end
  end
end

class ActiveSupport::TestCase
  include ::Minitest::Hooks
  include ::SelfCleaningSuite
  include ::TestInstrumentor
  include Rails.application.routes.url_helpers

  # Add more helper methods to be used by all tests here...
  def compare_hashes(reference, compare)
    ref = reference.to_a.flatten
    comp = compare.to_a.flatten
    if (ref.size > comp.size)
      difference = ref - comp
    else
      difference = comp - ref
    end
    Hash[*difference.flatten]
  end

  # mock environment variables
  # from https://gist.github.com/jazzytomato/79bb6ff516d93486df4e14169f4426af
  def mock_env(partial_env_hash)
    old = ENV.to_hash
    ENV.update partial_env_hash
    begin
      yield
    ensure
      ENV.replace old
    end
  end
end
