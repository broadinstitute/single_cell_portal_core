require 'test/unit'
require 'selenium-webdriver'
class UiTestSuite < Test::Unit::TestCase

# Unit Test that is actually a user flow test using the Selenium Webdriver to test dev UI directly
	def setup
		@driver = Selenium::WebDriver.for :firefox
		@base_url = "https://docker-host.com/single_cell"
		@accept_next_alert = true
		@driver.manage.timeouts.implicit_wait = 20
		@test_user = {
				email: 'test.user@gmail.com',
				password: 'password'
		}
	end

	def teardown
		@driver.quit
	end

	def element_present?(how, what)
		@driver.find_element(how, what)
		true
	rescue Selenium::WebDriver::Error::NoSuchElementError
		false
	end

	def verify(&blk)
		yield
	rescue Test::Unit::AssertionFailedError => ex
		@verification_errors << ex
	end

	def wait_until_page_loads(path)
		wait = Selenium::WebDriver::Wait.new(:timeout => 10)
		wait.until { @driver.current_url == path }
	end

	test 'should get home page' do
		@driver.get(@base_url)
		assert element_present?(:id, 'main-banner'), 'could not find index page title text'
		assert @driver.find_elements(:class, 'panel-primary').size >= 1, 'did not find any studies'
	end

	test 'should load nuc-seq study' do
		path = @base_url + '/study/nuc-seq'
		@driver.get(path)
		wait_until_page_loads(path)
		assert element_present?(:class, 'study-lead'), 'could not find study title'
		assert element_present?(:id, 'cluster-plot'), 'could not find study cluster plot'
		# load subcluster
		clusters = @driver.find_element(:id, 'cluster').find_elements(:tag_name, 'option')
		assert clusters.size == 6, 'incorrect number of sub-clusters found'
		clusters.select {|opt| opt.text == 'CA1'}.first.click
		Selenium::WebDriver::Wait.new(:timeout => 20).until { @driver.find_elements(:class, 'traces').size == 8 }
		legend = @driver.find_elements(:class, 'traces')
		assert legend.size == 8, "incorrect number of subclusters found in CA1, expected 8 - found #{legend.size}"
	end

end