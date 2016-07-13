require 'rubygems'
require 'test/unit'
require 'selenium-webdriver'

class UiTestSuite < Test::Unit::TestCase

# Unit Test that is actually a user flow test using the Selenium Webdriver to test dev UI directly
	def setup
		@driver = Selenium::WebDriver.for :firefox
		@base_url = "https://localhost/single_cell"
		@accept_next_alert = true
		@driver.manage.timeouts.implicit_wait = 20
		@test_user = {
				email: 'test.user@gmail.com',
				password: 'password'
		}
		@genes = %w(Leprel1 Dpf1 Erp29 Dpysl5 Ak7 Dgat2 Lsm11 Mamld1 Rbm17 Gad1 Prox1)
		@wait = Selenium::WebDriver::Wait.new(:timeout => 20)
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
		@wait.until { @driver.current_url == path }
	end

	test 'get home page' do
		@driver.get(@base_url)
		assert element_present?(:id, 'main-banner'), 'could not find index page title text'
		assert @driver.find_elements(:class, 'panel-primary').size >= 1, 'did not find any studies'
	end

	test 'load sNuc-Seq study' do
		path = @base_url + '/study/snuc-seq'
		@driver.get(path)
		wait_until_page_loads(path)
		assert element_present?(:class, 'study-lead'), 'could not find study title'
		assert element_present?(:id, 'cluster-plot'), 'could not find study cluster plot'
		# load subcluster
		clusters = @driver.find_element(:id, 'cluster').find_elements(:tag_name, 'option')
		assert clusters.size == 6, 'incorrect number of sub-clusters found'
		clusters.select {|opt| opt.text == 'CA1'}.first.click
		@wait.until { @driver.find_elements(:class, 'traces').size == 8 }
		legend = @driver.find_elements(:class, 'traces')
		assert legend.size == 8, "incorrect number of subclusters found in CA1, expected 8 - found #{legend.size}"
	end

	test 'download study data file' do
		path = @base_url + '/study/snuc-seq'
		@driver.get(path)
		wait_until_page_loads(path)
		download_section = @driver.find_element(:id, 'study-data-files')
		# gotcha when clicking, must wait until completes
		opened = download_section.click
		@wait.until { opened == 'ok'}
		files = @driver.find_elements(:class, 'dl-link')
		file_link = files.sample
		downloaded = file_link.click
		@wait.until {downloaded == 'ok'}
		assert downloaded == 'ok', 'could not click download link'
		assert file_link.displayed?, 'file link was not found'
	end

	test 'search for single gene' do
		path = @base_url + '/study/snuc-seq'
		@driver.get(path)
		wait_until_page_loads(path)
		# load random gene to search
		gene = @genes.sample
		search_box = @driver.find_element(:id, 'search_genes')
		search_box.send_key(gene)
		search_form = @driver.find_element(:id, 'search-genes-form')
		search_form.submit
		assert element_present?(:id, 'box-controls'), 'could not find expression boxplot'
		assert element_present?(:id, 'scatter-plots'), 'could not find expression scatter plots'
	end

	test 'search for multiple gene' do
		path = @base_url + '/study/snuc-seq'
		@driver.get(path)
		wait_until_page_loads(path)
		# load random genes to search
		genes = @genes.shuffle.take(rand(@genes.size) + 1)
		search_box = @driver.find_element(:id, 'search_genes')
		search_box.send_keys(genes.join(' '))
		search_form = @driver.find_element(:id, 'search-genes-form')
		search_form.submit
		assert element_present?(:id, 'plots'), 'could not find expression heatmap'
	end

	test 'load marker gene heatmap' do
		path = @base_url + '/study/snuc-seq'
		@driver.get(path)
		wait_until_page_loads(path)
		expression_list = @driver.find_element(:id, 'gene_set')
		opts = expression_list.find_elements(:tag_name, 'option').delete_if {|o| o.text == 'Please select a gene list'}
		list = opts.sample
		list.click
		assert element_present?(:id, 'box-controls'), 'could not find marker list expression boxplot'
		assert element_present?(:id, 'scatter-plots'), 'could not find marker list expression scatter plots'
	end

	test 'load marker gene box/scatter' do
		path = @base_url + '/study/snuc-seq'
		@driver.get(path)
		wait_until_page_loads(path)
		expression_list = @driver.find_element(:id, 'expression')
		opts = expression_list.find_elements(:tag_name, 'option').delete_if {|o| o.text == 'Please select a gene list'}
		list = opts.sample
		list.click
		assert element_present?(:id, 'plots'), 'could not find marker list expression heatmap'
	end

end