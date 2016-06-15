require 'test/unit'
require 'selenium-webdriver'
class UiTestSuite < Test::Unit::TestCase

# Unit Test that is actually a user flow test using the Selenium Webdriver to test dev UI directly
	def setup
		@driver = Selenium::WebDriver.for :firefox
		@base_url = ENV['HOSTNAME']
		@accept_next_alert = true
		@driver.manage.timeouts.implicit_wait = 5
		@test_user = {
				email: 'test.user@gmail.com',
				password: 'password'
		}
	end

end