require 'rubygems'
require 'test/unit'
require 'selenium-webdriver'

class UiTestSuite < Test::Unit::TestCase

# Unit Test that is actually a user flow test using the Selenium Webdriver to test dev UI directly
	def setup
		prefs = {
				:download => {
						:prompt_for_download => false,
						:default_directory => "/usr/local/bin/chromedriver"
				}
		}
		@driver = Selenium::WebDriver.for :firefox
		@base_url = 'https://localhost/single_cell'
		@accept_next_alert = true
		@driver.manage.timeouts.implicit_wait = 60
		# test user needs to be created manually before this will work
		@test_user = {
				email: 'test.user@gmail.com',
				password: 'password'
		}
		@share_user = {
				email: 'share.user@gmail.com',
				password: 'password'
		}
		@genes = %w(Leprel1 Dpf1 Erp29 Dpysl5 Ak7 Dgat2 Lsm11 Mamld1 Rbm17 Gad1 Prox1)
		@wait = Selenium::WebDriver::Wait.new(:timeout => 60)
		# configure path to sample data as appropriate for your system
		@test_data_path = '/Users/bistline/Documents/Data/single_cell/example/'
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

	# method to close a bootstrap modal by id
	def close_modal(id)
		modal = @driver.find_element(:id, id)
		dismiss = modal.find_element(:class, 'close')
		dismiss.click
		@wait.until {@driver.find_element(:tag_name, 'body')[:class].include?('modal-open') == false}
	end

	# wait until element is rendered and visible
	def wait_for_render(how, what)
		@wait.until {@driver.find_element(how, what).displayed? == true}
	end

	# method to wait for next button to enable
	def wait_for_next(btn)
		parent = btn.find_element(:xpath, '..')
		@wait.until {parent[:class].include?('enabled') == true}
	end

	# front end tests
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
		# load CA1 subcluster
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
		file_link = files.first
		@wait.until { file_link.displayed? }
		downloaded = file_link.click
		assert downloaded == 'ok', 'could not click download link'
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
		genes = @genes.shuffle.take(1 + rand(@genes.size) + 1)
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

	# admin backend test of entire study creation process as order needs to be maintained throughout
	# logs test user in, creates study, and deletes study on completion
	# uses sNuc-Seq data as inputs
	test 'create a study' do
		# log in first
		path = @base_url + '/studies/new'
		@driver.get path
		close_modal('message_modal')
		# send login info
		email = @driver.find_element(:id, 'user_email')
		email.send_keys(@test_user[:email])
		password = @driver.find_element(:id, 'user_password')
		password.send_keys(@test_user[:password])
		login_form = @driver.find_element(:id, 'new_user')
		login_form.submit
		wait_until_page_loads(path)
		close_modal('message_modal')

		# fill out study form
		study_form = @driver.find_element(:id, 'new_study')
		study_form.find_element(:id, 'study_name').send_keys('Test Study')
		study_form.find_element(:id, 'study_embargo').send_keys('2016-12-31')
		public = study_form.find_element(:id, 'study_public')
		public.send_keys('No')
		# add a share
		share = @driver.find_element(:id, 'add-study-share')
		@wait.until {share.displayed? == true}
		share_study = share.click
		@wait.until {share_study == 'ok'}
		share_email = study_form.find_element(:class, 'share-email')
		share_email.send_keys(@share_user[:email])
		# save study
		study_form.submit

		# upload cluster assignments
		wait_for_render(:id, 'assignments_form')
		modal = @driver.find_element(:id, 'message_modal')
		dismiss = modal.find_element(:class, 'close')
		dismiss.click
		upload_assignments = @driver.find_element(:id, 'upload-assignments')
		upload_assignments.send_keys(@test_data_path + 'cluster_assignments_example.txt')
		wait_for_render(:id, 'start-file-upload')
		upload_btn = @driver.find_element(:id, 'start-file-upload')
		upload_btn.click
		# wait for upload to complete and wizard to step forward
		wait_for_render(:id, 'parent_cluster_form')
		# close success modal
		wait_for_render(:id, 'upload-success-modal')
		close_modal('upload-success-modal')

		# upload cluster coordinates
		upload_clusters = @driver.find_element(:id, 'upload-clusters')
		upload_clusters.send_keys(@test_data_path + 'cluster_coordinates_example.txt')
		wait_for_render(:id, 'start-file-upload')
		upload_btn = @driver.find_element(:id, 'start-file-upload')
		upload_btn.click
		wait_for_render(:id, 'expression_form')
		# close success modal
		wait_for_render(:id, 'upload-success-modal')
		close_modal('upload-success-modal')

		# upload expression matrix
		upload_expression = @driver.find_element(:id, 'upload-expression')
		upload_expression.send_keys(@test_data_path + 'expression_matrix_example.txt')
		wait_for_render(:id, 'start-file-upload')
		upload_btn = @driver.find_element(:id, 'start-file-upload')
		upload_btn.click
		wait_for_render(:class, 'initialize_sub_clusters_form')
		# close success modal
		wait_for_render(:id, 'upload-success-modal')
		close_modal('upload-success-modal')

		# upload sub-cluster
		upload_clusters = @driver.find_element(:class, 'upload-sub-clusters')
		upload_clusters.send_keys(@test_data_path + 'sub_cluster_1_coordinates_example.txt')
		wait_for_render(:id, 'start-file-upload')
		upload_btn = @driver.find_element(:id, 'start-file-upload')
		upload_btn.click
		wait_for_render(:id, 'upload-success-modal')
		close_modal('upload-success-modal')
		next_btn = @driver.find_element(:id, 'next-btn')
		next_btn.click
		wait_for_render(:class, 'initialize_marker_genes_form')


		# upload marker gene list
		upload_clusters = @driver.find_element(:class, 'upload-marker-genes')
		upload_clusters.send_keys(@test_data_path + 'marker_1_gene_list.txt')
		wait_for_render(:id, 'start-file-upload')
		upload_btn = @driver.find_element(:id, 'start-file-upload')
		upload_btn.click
		wait_for_render(:id, 'upload-success-modal')
		close_modal('upload-success-modal')
		next_btn = @driver.find_element(:id, 'next-btn')
		next_btn.click
		wait_for_render(:class, 'initialize_fastq_form')

		# upload fastq
		upload_clusters = @driver.find_element(:class, 'upload-fastq')
		upload_clusters.send_keys(@test_data_path + 'cell_1_L1.fastq.gz')
		wait_for_render(:id, 'start-file-upload')
		upload_btn = @driver.find_element(:id, 'start-file-upload')
		upload_btn.click
		wait_for_render(:class, 'fastq-file')
		wait_for_render(:id, 'upload-success-modal')
		close_modal('upload-success-modal')
		next_btn = @driver.find_element(:id, 'next-btn')
		next_btn.click
		wait_for_render(:class, 'initialize_misc_form')

		# upload doc file
		upload_clusters = @driver.find_element(:class, 'upload-misc')
		upload_clusters.send_keys(@test_data_path + 'table_1.xlsx')
		wait_for_render(:id, 'start-file-upload')
		upload_btn = @driver.find_element(:id, 'start-file-upload')
		upload_btn.click
		wait_for_render(:class, 'documentation-file')
		# close success modal
		wait_for_render(:id, 'upload-success-modal')
		close_modal('upload-success-modal')

		# delete study
		@driver.get(@base_url + '/studies')
		wait_until_page_loads(@base_url + '/studies')
		@driver.find_element(:class, 'delete-btn').click
		@driver.switch_to.alert.accept
	end
end