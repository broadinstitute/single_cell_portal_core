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

class ActiveSupport::TestCase
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
end
