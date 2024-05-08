require 'rubygems'
require 'test/unit'
require 'selenium-webdriver'
require File.expand_path('ui_test_helper.rb', 'test')

# UI regression suite that exercises functionality through simulating user interactions via Webdriver
#
# REQUIREMENTS
#
# This test suite must be run from outside of Docker (i.e. your host machine) as Docker cannot access localhost on your machine when running in linked container mode.
# Therefore, the following languages/packages must be installed on your host:
#
# 1. RVM (or equivalent Ruby language management system)
# 2. Ruby >= 2.6.6 (currently, 2.6.6 is the version running inside the container)
# 3. Gems: rubygems, test-unit, selenium-webdriver (see Gemfile.lock for version requirements)
# 4. Google Chrome
# 5. Chromedriver (https://sites.google.com/a/chromium.org/chromedriver/); make sure the verison you install works with your version of chrome
# 6. Register for Terra (https://app.terra.bio) for both Google accounts (needed for auth & sharing acls)
# 7. The 'test email account' (see below) must be configured as a portal admin.  See 'ADMIN USER ACCOUNTS' in README.md for more information.

# USAGE
#
# To run the test suite:
#
# ruby test/ui_test_suite.rb [-n /pattern/] [--ignore-name /pattern/] -- -c=/path/to/chromedriver -e=testing.email@gmail.com -p='testing_email_password' -s=sharing.email@gmail.com -P='sharing_email_password' -o=order -d=/path/to/downloads -u=portal_url -E=environment -r=random_seed -v
#
# ui_test_suite.rb takes up to 14 arguments (4 are required):
# 1. path to your Chromedriver binary (passed with -c=)
# 2. path to your Chrome profile (passed with -C=): tests may fail to log in properly if you do not load the default chrome profile due to Google captchas
# 3. test email account (passed with -e=); REQUIRED. this must be a valid Google & FireCloud user and also configured as an 'admin' account in the portal
# 4. test email account password (passed with -p) REQUIRED. NOTE: you must quote the password to ensure it is passed correctly
# 5. share email account (passed with -s=); REQUIRED. this must be a valid Google & FireCloud user
# 6. share email account password (passed with -P) REQUIRED. NOTE: you must quote the password to ensure it is passed correctly
# 7. test order (passed with -o=); defaults to defined order (can be alphabetic or random, but random will most likely fail horribly
# 8. download directory (passed with -d=); place where files are downloaded on your OS, defaults to standard OSX location (/Users/`whoami`/Downloads)
# 9. portal url (passed with -u=); url to point tests at, defaults to https://localhost/single_cell
# 10. environment (passed with -E=); Rails environment that the target instance is running in.  Needed for constructing certain URLs
# 11. proxy (passed with -x=); option setting to set up a proxy for all Chromedriver traffic, no default
# 12. random seed (passed with -r=); random seed to use when running tests (will be needed if you're running front end tests against previously created studies from test suite)
# 13. verbose (passed with -v); run tests in verbose mode, will print extra logging messages where appropriate
# 14. interactive mode (passed with -i); run tests in interactive mode, which will open a chrome instance on your machine.  Default is to run headlessly via chromedriver
#
# IMPORTANT: if you do not use -- before the argument list and give the appropriate flag (with =), it is processed as a Test::Unit flag and ignored, and likely may
# cause the suite to fail to launch.
#
# Tests are named using a tag-based system so that they can be run in smaller groups to only cover specific portions of site functionality.
# They can be run singly or in groups by passing -n /pattern/ before the -- on the command line.  This will run any tests that match
# the given regular expression.  You can run all 'front-end' and 'admin' tests this way (although front-end tests require the tests studies to have been created already)

# For instance, to run all the tests that cover user annotations:
#
# ruby ui_test_suite.rb -n /user-annotation/ -- [rest of arguments]
#
# To run a single test by name, pass -n 'test: [name of test]', e.g -n 'test: front-end: view: study'
#
# Similarly, you can run all test but exclude some by using --ignore-name /pattern/.  Also, you can combine -n and --ignore-name to run all matching
# test, excluding those matched by ignore-name.
#
# NOTE: when running this test harness, it tends to perform better on an external monitor.  Webdriver is very sensitive to elements not
# being clickable, and the more screen area available, the better.



## INITIALIZATION & CONFIGURATION

# parse arguments and set global variables
parse_test_arguments(ARGV)

# print configuration
puts "Chromedriver Binary: #{$chromedriver_path}"
puts "Testing email: #{$test_email}"
puts "Sharing email: #{$share_email}"
puts "Download directory: #{$download_dir}"
puts "Portal URL: #{$portal_url}"
puts "Environment: #{$env}"
puts "Webdriver Proxy: #{$webdriver_proxy}"
puts "Random Seed: #{$random_seed}"
puts "Headless: #{$headless}"
puts "Verbose: #{$verbose}"

# make sure download & chromedriver paths exist and portal url is valid, otherwise kill tests before running and print usage
if !File.exists?($chromedriver_path)
  puts "No Chromedriver binary found at #{$chromedriver_path}"
  puts $usage
  exit(1)
elsif !Dir.exist?($download_dir)
  puts "No download directory found at #{$download_dir}"
  puts $usage
  exit(1)
elsif !$portal_url.start_with?('https://') || $portal_url[($portal_url.size - 12)..($portal_url.size - 1)] != '/single_cell'
  puts "Invalid portal url: #{$portal_url}; must begin with https:// and end with /single_cell"
  puts $usage
  exit(1)
end

class UiTestSuite < Test::Unit::TestCase
  self.test_order = $order

  # setup is called before every test is run, this instantiates the driver and configures waits and other variables needed
  def setup
    # disable the 'save your password' prompt
    caps = Selenium::WebDriver::Remote::Capabilities.chrome("chromeOptions" => {'prefs' => {'credentials_enable_service' => false}})
    if !$webdriver_proxy.nil?
      caps.proxy = Selenium::WebDriver::Proxy.new(http: $webdriver_proxy, ssl: $webdriver_proxy)
    end
    options = Selenium::WebDriver::Chrome::Options.new
    options.add_argument('--enable-webgl-draft-extensions')
    options.add_argument('--incognito')
    options.add_argument('--allow-insecure-localhost')
    if $headless
      options.add_argument('--disable-gpu')
      options.add_argument('--no-sandbox')
      options.add_argument('--headless')
      options.add_argument('--disable-dev-shm-usage')
    end
    @driver = Selenium::WebDriver::Driver.for :chrome, driver_path: $chromedriver_dir,
                                              options: options, desired_capabilities: caps,
                                              driver_opts: {log_path: '/tmp/webdriver.log'}
    # @driver.manage.window.maximize
    @base_url = $portal_url
    @accept_next_alert = true
    @driver.manage.timeouts.implicit_wait = 15
    # only Google auth

    @genes = %w(Itm2a Sergef Chil5 Fam109a Dhx9 Ssu72 Olfr1018 Fam71e2 Eif2b2)
    @wait = Selenium::WebDriver::Wait.new(:timeout => 30)
    @test_data_path = File.expand_path(File.join(File.dirname(__FILE__), 'test_data')) + '/'
    @base_path = File.expand_path(File.join(File.dirname(__FILE__), '..'))
    puts "\n"
  end

  # called on completion of every test (whether it passes or fails)
  def teardown
    invalidate_google_session
    @driver.quit
  end

  ###
  #
  # ADMIN & CONFIGURATION TESTS
  #
  ###

  ##
  ## CREATE STUDIES
  ## These tests create the main studies used in downstream tests
  ##

  # create basic test study
  test 'admin: create-study: sharing: configurations: validation: download: user-annotation: workflows: user-profiles: branding-groups: public' do
    puts "#{File.basename(__FILE__)}: '#{self.method_name}'"

    @driver.get @base_url

    # log in as user #1
    login($test_email, $test_email_password)
    @driver.get @base_url + '/studies/new'

    # fill out study form
    study_form = @driver.find_element(:id, 'new_study')
    study_form.find_element(:id, 'study_name').send_keys("Test Study #{$random_seed}")
    public = study_form.find_element(:id, 'study_public')
    public.send_keys('Yes')
    # add a share
    share = @driver.find_element(:id, 'add-study-share')
    @wait.until {share.displayed?}
    share.click
    share_email = study_form.find_element(:class, 'share-email')
    share_email.send_keys($share_email)
    share_permission = study_form.find_element(:class, 'share-permission')
    share_permission.send_keys('Edit')
    # add external resource
    add_resource = @driver.find_element(:id, 'add-external-resource')
    add_resource.click
    resource_title = @driver.find_element(:class, 'external-resource-title')
    resource_title.send_keys('PubMed')
    resource_description = @driver.find_element(:class, 'external-resource-description')
    resource_description.send_keys('PubMed link to paper')
    resource_url = @driver.find_element(:class, 'external-resource-url')
    resource_url.send_keys('https://www.ncbi.nlm.nih.gov/pubmed/')
    # save study
    save_study = @driver.find_element(:id, 'save-study')
    save_study.click

    close_modal('message_modal')
    # set species info if available
    species_dropdown = @driver.find_element(:id, 'study_file_taxon_id')
    opts = species_dropdown.find_elements(:tag_name, 'option')
    available_species = opts.delete_if {|opt| opt['value'] == ''}
    if available_species.any?
      species_dropdown.send_keys(available_species.sample.text)
    end
    # upload expression matrix
    upload_expression = @driver.find_element(:id, 'upload-expression')
    upload_expression.send_keys(@test_data_path + 'expression_matrix_example.txt')
    wait_for_render(:id, 'start-file-upload')
    upload_btn = @driver.find_element(:id, 'start-file-upload')
    sleep(0.5)
    upload_btn.click
    # close success modal
    close_modal('upload-success-modal')

    # upload a second expression file
    new_expression = @driver.find_element(:class, 'add-expression')
    new_expression.click
    scroll_to(:bottom)
    exp_2_form = @driver.find_element(:class, 'new-expression-form')
    species_dropdown = exp_2_form.find_element(:id, 'study_file_taxon_id')
    opts = species_dropdown.find_elements(:tag_name, 'option')
    available_species = opts.delete_if {|opt| opt['value'] == ''}
    if available_species.any?
      species_dropdown.send_keys(available_species.sample.text)
    end
    upload_expression_2 = exp_2_form.find_element(:id, 'upload-expression')
    upload_expression_2.send_keys(@test_data_path + 'expression_matrix_example_2.txt')
    wait_for_render(:id, 'start-file-upload')
    upload_btn = @driver.find_element(:id, 'start-file-upload')
    sleep(0.5)
    upload_btn.click
    # close success modal
    close_modal('upload-success-modal')
    next_btn = @driver.find_element(:id, 'next-btn')
    next_btn.click

    # upload metadata
    wait_for_render(:id, 'metadata_form')
    upload_metadata = @driver.find_element(:id, 'upload-metadata')
    upload_metadata.send_keys(@test_data_path + 'metadata_example2.txt')
    wait_for_render(:id, 'start-file-upload')
    upload_btn = @driver.find_element(:id, 'start-file-upload')
    sleep(0.5)
    upload_btn.click
    close_modal('upload-success-modal')

    # upload cluster
    cluster_form_1 = @driver.find_element(:class, 'initialize_ordinations_form')
    cluster_name = cluster_form_1.find_element(:class, 'filename')
    cluster_name.send_keys('Test Cluster 1')
    upload_cluster = cluster_form_1.find_element(:class, 'upload-clusters')
    upload_cluster.send_keys(@test_data_path + 'cluster_example_2.txt')
    wait_for_render(:id, 'start-file-upload')
    # add labels and axis ranges
    cluster_form_1.find_element(:id, :study_file_x_axis_min).send_keys(-100)
    cluster_form_1.find_element(:id, :study_file_x_axis_max).send_keys(100)
    cluster_form_1.find_element(:id, :study_file_y_axis_min).send_keys(-75)
    cluster_form_1.find_element(:id, :study_file_y_axis_max).send_keys(75)
    cluster_form_1.find_element(:id, :study_file_z_axis_min).send_keys(-125)
    cluster_form_1.find_element(:id, :study_file_z_axis_max).send_keys(125)
    cluster_form_1.find_element(:id, :study_file_x_axis_label).send_keys('X Axis')
    cluster_form_1.find_element(:id, :study_file_y_axis_label).send_keys('Y Axis')
    cluster_form_1.find_element(:id, :study_file_z_axis_label).send_keys('Z Axis')
    # perform upload
    upload_btn = cluster_form_1.find_element(:id, 'start-file-upload')
    upload_btn.click
    close_modal('upload-success-modal')

    # upload a second cluster
    new_cluster = @driver.find_element(:class, 'add-cluster')
    new_cluster.click
    scroll_to(:bottom)
    # will be second instance since there are two forms
    cluster_form_2 = @driver.find_element(:class, 'new-cluster-form')
    cluster_name_2 = cluster_form_2.find_element(:class, 'filename')
    cluster_name_2.send_keys('Test Cluster 2')
    upload_cluster_2 = cluster_form_2.find_element(:class, 'upload-clusters')
    upload_cluster_2.send_keys(@test_data_path + 'cluster_2_example_2.txt')
    wait_for_render(:id, 'start-file-upload')
    scroll_to(:bottom)
    upload_btn_2 = cluster_form_2.find_element(:id, 'start-file-upload')
    sleep(0.5)
    upload_btn_2.click
    close_modal('upload-success-modal')
    next_btn = @driver.find_element(:id, 'next-btn')
    next_btn.click

    # upload a coordinate labels file
    wait_for_render(:class, 'add-coordinate-labels')
    add_coords_btn = @driver.find_element(:class, 'add-coordinate-labels')
    add_coords_btn.click
    wait_for_render(:class, 'initialize_labels_form')
    coords_form = @driver.find_element(:class, 'initialize_labels_form')
    cluster_select = coords_form.find_element(:id, 'study_file_options_cluster_file_id')
    cluster_select.send_keys('Test Cluster 1')
    upload_coords = coords_form.find_element(:class, 'upload-labels')
    upload_coords.send_keys(@test_data_path + 'coordinate_labels_1.txt')
    upload_btn = coords_form.find_element(:id, 'start-file-upload')
    sleep(0.5)
    upload_btn.click
    close_modal('upload-success-modal')
    next_btn = @driver.find_element(:id, 'next-btn')
    next_btn = @driver.find_element(:id, 'next-btn')
    next_btn.click

    # upload right fastq
    wait_for_render(:class, 'initialize_primary_data_form')
    fastq_form = @driver.find_element(:class, 'new-fastq-form')
    species_dropdown = fastq_form.find_element(:id, 'study_file_taxon_id')
    opts = species_dropdown.find_elements(:tag_name, 'option')
    available_species = opts.delete_if {|opt| opt['value'] == '' || opt.text.downcase == 'human' }
    if available_species.any?
      species_dropdown.send_keys(available_species.select {|s| !s.text != 'human'}.sample.text)
    end
    upload_fastq = fastq_form.find_element(:class, 'upload-fastq')
    upload_fastq.send_keys(@test_data_path + 'cell_1_R1_001.fastq.gz')
    wait_for_render(:id, 'start-file-upload')
    upload_btn = fastq_form.find_element(:id, 'start-file-upload')
    sleep(0.5)
    upload_btn.click
    close_modal('upload-success-modal')

    # upload left fastq
    add_fastq = @driver.find_element(:class, 'add-primary-data')
    add_fastq.click
    wait_for_render(:class, 'new-fastq-form')
    new_fastq_form = @driver.find_element(class: 'new-fastq-form')
    species_dropdown = new_fastq_form.find_element(:id, 'study_file_taxon_id')
    opts = species_dropdown.find_elements(:tag_name, 'option')
    available_species = opts.delete_if {|opt| opt['value'] == '' || opt.text.downcase == 'human' }
    if available_species.any?
      species_dropdown.send_keys(available_species.select {|s| !s.text != 'human'}.sample.text)
    end
    new_upload_fastq = new_fastq_form.find_element(:class, 'upload-fastq')
    new_upload_fastq.send_keys(@test_data_path + 'cell_1_I1_001.fastq.gz')
    wait_for_render(:id, 'start-file-upload')
    upload_btn = new_fastq_form.find_element(:id, 'start-file-upload')
    sleep(0.5)
    upload_btn.click
    close_modal('upload-success-modal')
    next_btn = @driver.find_element(:id, 'next-btn')
    next_btn.click

    # upload marker gene list
    wait_for_render(:class, 'initialize_marker_genes_form')
    marker_form = @driver.find_element(:class, 'initialize_marker_genes_form')
    marker_file_name = marker_form.find_element(:id, 'study_file_name')
    marker_file_name.send_keys('Test Gene List')
    upload_markers = marker_form.find_element(:class, 'upload-marker-genes')
    upload_markers.send_keys(@test_data_path + 'marker_1_gene_list.txt')
    wait_for_render(:id, 'start-file-upload')
    upload_btn = marker_form.find_element(:id, 'start-file-upload')
    sleep(0.5)
    upload_btn.click
    close_modal('upload-success-modal')
    next_btn = @driver.find_element(:id, 'next-btn')
    next_btn.click

    # upload doc file
    wait_for_render(:class, 'initialize_misc_form')
    upload_doc = @driver.find_element(:class, 'upload-misc')
    upload_doc.send_keys(@test_data_path + 'table_1.xlsx')
    wait_for_render(:id, 'start-file-upload')
    upload_btn = @driver.find_element(:id, 'start-file-upload')
    sleep(0.5)
    upload_btn.click
    # close success modal
    close_modal('upload-success-modal')

    # change attributes on file to validate update function
    misc_form = @driver.find_element(:class, 'initialize_misc_form')
    desc_field = misc_form.find_element(:id, 'study_file_description')
    desc_field.send_keys('Supplementary table')
    save_btn = misc_form.find_element(:class, 'save-study-file')
    save_btn.click
    wait_for_modal_open('study-file-notices')
    close_modal('study-file-notices')

    # now check newly created study info page
    studies_path = @base_url + '/studies'
    @driver.get studies_path

    show_study = @driver.find_element(:class, "test-study-#{$random_seed}-show")
    show_study.click

    # wait for parsing to complete on remote jobs
    wait_for_file_parse('expression_matrix_example_txt-parse-status')
    wait_for_file_parse('expression_matrix_example_2_txt-parse-status')
    wait_for_file_parse('metadata_example2_txt-parse-status')
    wait_for_file_parse('cluster_example_2_txt-parse-status')
    wait_for_file_parse('cluster_2_example_2_txt-parse-status')

    # verify that counts are correct, this will ensure that everything uploaded & parsed correctly
    cell_count = @driver.find_element(:id, 'cell-count').text.to_i
    gene_count = @driver.find_element(:id, 'gene-count').text.to_i
    cluster_count = @driver.find_element(:id, 'cluster-count').text.to_i
    gene_list_count = @driver.find_element(:id, 'precomputed-count').text.to_i
    metadata_count = @driver.find_element(:id, 'metadata-count').text.to_i
    cluster_annot_count = @driver.find_element(:id, 'cluster-annotation-count').text.to_i
    study_file_count = @driver.find_element(:id, 'study-file-count').text.to_i
    primary_data_count = @driver.find_element(:id, 'primary-data-count').text.to_i
    share_count = @driver.find_element(:id, 'share-count').text.to_i
    resources_count = @driver.find_element(:id, 'resources-count').text.to_i

    assert cell_count == 30, "did not find correct number of cells, expected 30 but found #{cell_count}"
    assert gene_count == 19, "did not find correct number of genes, expected 19 but found #{gene_count}"
    assert cluster_count == 2, "did not find correct number of clusters, expected 2 but found #{cluster_count}"
    assert gene_list_count == 1, "did not find correct number of gene lists, expected 1 but found #{gene_list_count}"
    assert metadata_count == 3, "did not find correct number of metadata objects, expected 3 but found #{metadata_count}"
    assert cluster_annot_count == 4, "did not find correct number of cluster annotations, expected 4 but found #{cluster_annot_count}"
    assert study_file_count == 8, "did not find correct number of study files, expected 8 but found #{study_file_count}"
    assert primary_data_count == 2, "did not find correct number of primary data files, expected 2 but found #{primary_data_count}"
    assert share_count == 1, "did not find correct number of study shares, expected 1 but found #{share_count}"
    assert resources_count == 1, "did not find correct number of external resources, expected 1 but found #{resources_count}"

    puts "#{File.basename(__FILE__)}: '#{self.method_name}' successful!"
  end

  # create a 2d scatter study for use in user annotation testing
  test 'admin: create-study: user-annotation: 2d' do
    puts "#{File.basename(__FILE__)}: '#{self.method_name}'"

    # log in first
    @driver.get @base_url
    login($test_email, $test_email_password)
    @driver.get @base_url + '/studies/new'
    # fill out study form
    study_form = @driver.find_element(:id, 'new_study')
    study_form.find_element(:id, 'study_name').send_keys("twod Study #{$random_seed}")
    public = study_form.find_element(:id, 'study_public')
    public.send_keys('Yes')
    # add a share
    share = @driver.find_element(:id, 'add-study-share')
    @wait.until {share.displayed?}
    share.click
    share_email = study_form.find_element(:class, 'share-email')
    share_email.send_keys($share_email)
    share_permission = study_form.find_element(:class, 'share-permission')
    share_permission.send_keys('Edit')
    # save study
    save_study = @driver.find_element(:id, 'save-study')
    save_study.click

    # upload expression matrix
    close_modal('message_modal')
    exp_form = @driver.find_element(:class, 'new-expression-form')
    species_dropdown = exp_form.find_element(:id, 'study_file_taxon_id')
    opts = species_dropdown.find_elements(:tag_name, 'option')
    available_species = opts.delete_if {|opt| opt['value'] == ''}
    if available_species.any?
      species_dropdown.send_keys(available_species.sample.text)
    end
    upload_expression = exp_form.find_element(:id, 'upload-expression')
    upload_expression.send_keys(@test_data_path + 'expression_matrix_example.txt')
    wait_for_render(:id, 'start-file-upload')
    upload_btn = @driver.find_element(:id, 'start-file-upload')
    sleep(0.5)
    upload_btn.click
    # close success modal
    close_modal('upload-success-modal')
    next_btn = @driver.find_element(:id, 'next-btn')
    next_btn.click

    # upload metadata
    wait_for_render(:id, 'metadata_form')
    upload_metadata = @driver.find_element(:id, 'upload-metadata')
    upload_metadata.send_keys(@test_data_path + 'metadata_example.txt')
    wait_for_render(:id, 'start-file-upload')
    upload_btn = @driver.find_element(:id, 'start-file-upload')
    sleep(0.5)
    upload_btn.click
    close_modal('upload-success-modal')

    # upload cluster
    cluster_form_1 = @driver.find_element(:class, 'initialize_ordinations_form')
    cluster_name = cluster_form_1.find_element(:class, 'filename')
    cluster_name.send_keys('Test Cluster 1')
    upload_cluster = cluster_form_1.find_element(:class, 'upload-clusters')
    upload_cluster.send_keys(@test_data_path + 'cluster_2d_example.txt')
    wait_for_render(:id, 'start-file-upload')

    # perform upload
    upload_btn = cluster_form_1.find_element(:id, 'start-file-upload')
    sleep(0.5)
    upload_btn.click
    close_modal('upload-success-modal')

    # upload marker gene list
    scroll_to(:top)
    gene_list_tab = @driver.find_element(:id, 'initialize_marker_genes_form_nav')
    gene_list_tab.click
    marker_form = @driver.find_element(:class, 'initialize_marker_genes_form')
    marker_file_name = marker_form.find_element(:id, 'study_file_name')
    marker_file_name.send_keys('Test Gene List')
    upload_markers = marker_form.find_element(:class, 'upload-marker-genes')
    upload_markers.send_keys(@test_data_path + 'marker_1_gene_list.txt')
    wait_for_render(:id, 'start-file-upload')
    upload_btn = marker_form.find_element(:id, 'start-file-upload')
    sleep(0.5)
    upload_btn.click
    close_modal('upload-success-modal')

    # confirm all files uploaded
    studies_path = @base_url + '/studies'
    @driver.get studies_path

    study_file_count = @driver.find_element(:id, "twod-study-#{$random_seed}-study-file-count").text.to_i
    assert study_file_count == 4, "did not find correct number of files, expected 4 but found #{study_file_count}"

    puts "#{File.basename(__FILE__)}: '#{self.method_name}' successful!"
  end

  # create private study for testing visibility/edit restrictions
  test 'admin: create-study: sharing: download: branding-groups: private' do
    puts "#{File.basename(__FILE__)}: '#{self.method_name}'"

    # log in first
    @driver.get @base_url
    login($test_email, $test_email_password)
    @driver.get @base_url + '/studies/new'

    # fill out study form
    study_form = @driver.find_element(:id, 'new_study')
    study_form.find_element(:id, 'study_name').send_keys("Private Study #{$random_seed}")
    public = study_form.find_element(:id, 'study_public')
    public.send_keys('No')
    # save study
    save_study = @driver.find_element(:id, 'save-study')
    save_study.click

    # upload expression matrix
    close_modal('message_modal')
    exp_form = @driver.find_element(:class, 'new-expression-form')
    species_dropdown = exp_form.find_element(:id, 'study_file_taxon_id')
    opts = species_dropdown.find_elements(:tag_name, 'option')
    available_species = opts.delete_if {|opt| opt['value'] == ''}
    if available_species.any?
      species_dropdown.send_keys(available_species.sample.text)
    end
    upload_expression = exp_form.find_element(:id, 'upload-expression')
    upload_expression.send_keys(@test_data_path + 'expression_matrix_example.txt')
    wait_for_render(:id, 'start-file-upload')
    upload_btn = @driver.find_element(:id, 'start-file-upload')
    sleep(0.5)
    upload_btn.click
    # close success modal
    close_modal('upload-success-modal')
    next_btn = @driver.find_element(:id, 'next-btn')
    next_btn.click

    # upload metadata
    wait_for_render(:id, 'metadata_form')
    upload_metadata = @driver.find_element(:id, 'upload-metadata')
    upload_metadata.send_keys(@test_data_path + 'metadata_example.txt')
    wait_for_render(:id, 'start-file-upload')
    upload_btn = @driver.find_element(:id, 'start-file-upload')
    sleep(0.5)
    upload_btn.click
    close_modal('upload-success-modal')

    # upload cluster
    cluster_form_1 = @driver.find_element(:class, 'initialize_ordinations_form')
    cluster_name = cluster_form_1.find_element(:class, 'filename')
    cluster_name.send_keys('Test Cluster 1')
    upload_cluster = cluster_form_1.find_element(:class, 'upload-clusters')
    upload_cluster.send_keys(@test_data_path + 'cluster_example.txt')
    wait_for_render(:id, 'start-file-upload')
    upload_btn = @driver.find_element(:id, 'start-file-upload')
    sleep(0.5)
    upload_btn.click
    close_modal('upload-success-modal')

    # upload marker gene list
    scroll_to(:top)
    gene_list_tab = @driver.find_element(:id, 'initialize_marker_genes_form_nav')
    gene_list_tab.click
    marker_form = @driver.find_element(:class, 'initialize_marker_genes_form')
    marker_file_name = marker_form.find_element(:id, 'study_file_name')
    marker_file_name.send_keys('Test Gene List')
    upload_markers = marker_form.find_element(:class, 'upload-marker-genes')
    upload_markers.send_keys(@test_data_path + 'marker_1_gene_list.txt')
    wait_for_render(:id, 'start-file-upload')
    upload_btn = marker_form.find_element(:id, 'start-file-upload')
    sleep(0.5)
    upload_btn.click
    close_modal('upload-success-modal')
    next_btn = @driver.find_element(:id, 'next-btn')
    next_btn.click

    # add misc file
    add_misc = @driver.find_element(:class, 'add-misc')
    add_misc.click
    new_misc_form = @driver.find_element(:class, 'new-misc-form')
    upload_doc = new_misc_form.find_element(:class, 'upload-misc')
    upload_doc.send_keys(@test_data_path + 'README.txt')
    wait_for_render(:id, 'start-file-upload')
    upload_btn = @driver.find_element(:id, 'start-file-upload')
    sleep(0.5)
    upload_btn.click
    # close modal
    close_modal('upload-success-modal')

    puts "#{File.basename(__FILE__)}: '#{self.method_name}' successful!"
  end

  # text gzip parsing of expression matrices
  test 'admin: create-study: gzip expression matrix' do
    puts "#{File.basename(__FILE__)}: '#{self.method_name}'"

    # log in first
    @driver.get @base_url
    login($test_email, $test_email_password)
    @driver.get @base_url + '/studies/new'

    # fill out study form
    study_form = @driver.find_element(:id, 'new_study')
    study_form.find_element(:id, 'study_name').send_keys("Gzip Parse #{$random_seed}")
    # save study
    save_study = @driver.find_element(:id, 'save-study')
    save_study.click

    # upload bad expression matrix
    close_modal('message_modal')
    exp_form = @driver.find_element(:class, 'new-expression-form')
    species_dropdown = exp_form.find_element(:id, 'study_file_taxon_id')
    opts = species_dropdown.find_elements(:tag_name, 'option')
    available_species = opts.delete_if {|opt| opt['value'] == ''}
    if available_species.any?
      species_dropdown.send_keys(available_species.sample.text)
    end
    upload_expression = exp_form.find_element(:id, 'upload-expression')
    upload_expression.send_keys(@test_data_path + 'expression_matrix_example_gzipped.txt.gz')
    wait_for_render(:id, 'start-file-upload')
    upload_btn = @driver.find_element(:id, 'start-file-upload')
    sleep(0.5)
    upload_btn.click
    close_modal('upload-success-modal')

    # verify parse completed
    studies_path = @base_url + '/studies'
    @driver.get studies_path
    wait_until_page_loads(studies_path)
    study_file_count = @driver.find_element(:id, "gzip-parse-#{$random_seed}-study-file-count")
    assert study_file_count.text == '1', "found incorrect number of study files; expected 1 and found #{study_file_count.text}"
    puts "#{File.basename(__FILE__)}: '#{self.method_name}' successful"
  end

  # test bundling process for file uploads
  # also tests ParseUtils.cell_ranger_expression_parse on small 100x25 gene-barcode matrix
  test 'admin: create-study: file bundles' do
    puts "#{File.basename(__FILE__)}: '#{self.method_name}'"

    # log in first
    @driver.get @base_url
    login($test_email, $test_email_password)
    @driver.get @base_url + '/studies/new'

    # fill out study form
    study_form = @driver.find_element(:id, 'new_study')
    study_form.find_element(:id, 'study_name').send_keys("File Bundle #{$random_seed}")
    # save study
    save_study = @driver.find_element(:id, 'save-study')
    save_study.click

    # upload coordinate expression matrix
    close_modal('message_modal')
    matrix_form = @driver.find_element(:class, 'initialize_expression_form')
    matrix_type = matrix_form.find_element(:id, 'study_file_file_type')
    matrix_type.send_keys('MM Coordinate Matrix')
    species_dropdown = matrix_form.find_element(:id, 'study_file_taxon_id')
    opts = species_dropdown.find_elements(:tag_name, 'option')
    available_species = opts.delete_if {|opt| opt['value'] == ''}
    if available_species.any?
      species_dropdown.send_keys(available_species.sample.text)
    end
    upload_expression = matrix_form.find_element(:id, 'upload-expression')
    upload_expression.send_keys(@test_data_path + 'GRCh38/test_matrix.mtx')
    wait_for_render(:id, 'start-file-upload')
    upload_btn = @driver.find_element(:id, 'start-file-upload')
    sleep(0.5)
    upload_btn.click
    close_modal('upload-success-modal')

    # upload genes & barcodes files
    genes_file_form = @driver.find_element(:class, 'new-10x-genes-file-file-form')
    upload_genes = genes_file_form.find_element(:id, 'upload-bundled-file')
    upload_genes.send_keys(@test_data_path + 'GRCh38/test_genes.tsv')
    wait_for_render(:id, 'start-file-upload')
    upload_btn = genes_file_form.find_element(:id, 'start-file-upload')
    sleep(0.5)
    upload_btn.click
    close_modal('upload-success-modal')

    barcodes_file_form = @driver.find_element(:class, 'new-10x-barcodes-file-file-form')
    upload_barcodes = barcodes_file_form.find_element(:id, 'upload-bundled-file')
    upload_barcodes.send_keys(@test_data_path + 'GRCh38/barcodes.tsv')
    wait_for_render(:id, 'start-file-upload')
    upload_btn = barcodes_file_form.find_element(:id, 'start-file-upload')
    sleep(0.5)
    upload_btn.click
    close_modal('upload-success-modal')

    # verify parse has initiated
    sleep(5) # give it 5 seconds to kick off before checking
    studies_path = @base_url + '/studies'
    @driver.get studies_path
    wait_until_page_loads(studies_path)
    study_file_count = @driver.find_element(:id, "file-bundle-#{$random_seed}-study-file-count")
    assert study_file_count.text == '3', "found incorrect number of study files; expected 3 and found #{study_file_count.text}"
    show_study = @driver.find_element(:class, "file-bundle-#{$random_seed}-show")
    show_study.click

    # check counts
    gene_count = @driver.find_element(:id, 'gene-count').text.chomp(' genes').to_i
    i = 0
    while gene_count == 0 && i < 24 # give parse 2 minutes to complete, should be enough
      sleep 5
      @driver.navigate.refresh
      gene_count = @driver.find_element(:id, 'gene-count').text.chomp(' genes').to_i
      i += 1
    end
    assert gene_count == 100, "Did not properly parse coordinate matrix triplet, expected 100 genes but found #{gene_count}"
    @driver.get @base_url + '/studies'
    delete = @driver.find_element(:class, "file-bundle-#{$random_seed}-delete")
    delete.click
    accept_alert
    close_modal('message_modal')
    puts "#{File.basename(__FILE__)}: '#{self.method_name}' successful"
  end

  # test embargo functionality
  test 'admin: create-study: embargo' do
    puts "#{File.basename(__FILE__)}: '#{self.method_name}'"

    # log in first
    @driver.get @base_url
    login($test_email, $test_email_password)
    @driver.get @base_url + '/studies/new'

    # fill out study form
    study_form = @driver.find_element(:id, 'new_study')
    study_form.find_element(:id, 'study_name').send_keys("Embargo Study #{$random_seed}")
    embargo_date = (Date.today + 1).to_s
    study_form.find_element(:id, 'study_embargo').send_keys(embargo_date)

    # save study
    save_study = @driver.find_element(:id, 'save-study')
    save_study.click

    # upload expression matrix
    close_modal('message_modal')
    exp_form = @driver.find_element(:class, 'new-expression-form')
    species_dropdown = exp_form.find_element(:id, 'study_file_taxon_id')
    opts = species_dropdown.find_elements(:tag_name, 'option')
    available_species = opts.delete_if {|opt| opt['value'] == ''}
    if available_species.any?
      species_dropdown.send_keys(available_species.sample.text)
    end
    upload_expression = exp_form.find_element(:id, 'upload-expression')
    upload_expression.send_keys(@test_data_path + 'expression_matrix_example.txt')
    wait_for_render(:id, 'start-file-upload')
    upload_btn = @driver.find_element(:id, 'start-file-upload')
    sleep(0.5)
    upload_btn.click
    # close modal
    close_modal('upload-success-modal')

    # verify user can still download data
    embargo_url = @base_url + "/study/embargo-study-#{$random_seed}"
    @driver.get embargo_url
    @wait.until {element_present?(:id, 'study-download')}
    open_ui_tab('study-download')
    i = 0
    link_present = element_present?(:class, 'dl-link')
    while !link_present
      sleep 1
      @driver.get embargo_url
      @wait.until {element_present?(:id, 'study-download')}
      open_ui_tab('study-download')
      link_present = element_present?(:class, 'dl-link')
      i += 1
    end
    download_links = @driver.find_elements(:class, 'dl-link')
    assert download_links.size == 1, "did not find correct number of download links, expected 1 but found #{download_links.size}"

    # logout
    logout_from_portal

    # login as share user
    login_as_other($share_email, $share_email_password)

    # now assert download links do not load
    @driver.get embargo_url
    @wait.until {element_present?(:id, 'study-download')}
    open_ui_tab('study-download')
    embargo_links = @driver.find_elements(:class, 'embargoed-file')
    assert embargo_links.size == 1, "did not find correct number of embargo links, expected 1 but found #{embargo_links.size}"

    # make sure embargo redirect is in place
    study_accession = extract_accession_from_url(@driver.current_url)
    data_url = @base_url + "/data/public/#{study_accession}/embargo-study-#{$random_seed}?filename=expression_matrix_example.txt"
    @driver.get data_url
    wait_for_modal_open('message_modal')
    alert_text = @driver.find_element(:id, 'alert-content').text
    expected_alert = "You may not download any data from this study until #{(Date.today + 1).strftime("%B %d, %Y")}."
    assert alert_text == expected_alert, "did not find correct alert, expected '#{expected_alert}' but found '#{alert_text}'"

    puts "#{File.basename(__FILE__)}: '#{self.method_name}' successful!"
  end

  ##
  ## STUDY VALIDATION
  ## Validate newly created studies and test various validations and privacy restrictions
  ##

  # verify that recently created study uploaded to firecloud
  test 'admin: validation: verify firecloud workspace' do
    puts "#{File.basename(__FILE__)}: '#{self.method_name}'"

    @driver.get @base_url
    login($test_email, $test_email_password)
    @driver.get @base_url + '/studies'

    show_study = @driver.find_element(:class, "test-study-#{$random_seed}-show")
    show_study.click

    # verify firecloud workspace creation
    firecloud_link = @driver.find_element(:id, 'firecloud-link')
    firecloud_url = "https://app.terra.bio/#workspaces/single-cell-portal-#{$env}/test-study-#{$random_seed}"
    firecloud_link.click
    @driver.switch_to.window(@driver.window_handles.last)
    sleep(1) # we need a sleep to let the driver catch up, otherwise we can get stuck in an inbetween state
    accept_firecloud_tos
    completed = @driver.find_elements(:class, 'fa-pen')
    assert completed.size >= 1, 'did not provision workspace properly'
    assert @driver.current_url == firecloud_url, 'did not open firecloud workspace'

    # verify gcs bucket and uploads
    @driver.switch_to.window(@driver.window_handles.first)
    sleep(1)
    gcs_link = @driver.find_element(:id, 'gcs-link')
    gcs_link.click
    @driver.switch_to.window(@driver.window_handles.last)
    sleep(1)
    # select the correct user
    user_link = @driver.find_element(:xpath, "//div[@data-email='#{$test_email}']")
    user_link.click
    table = @driver.find_element(:id, 'p6n-storage-objects-table')
    table_body = table.find_element(:tag_name, 'tbody')
    files = table_body.find_elements(:tag_name, 'tr')
    assert files.size == 10, "did not find correct number of files, expected 10 but found #{files.size}"
    puts "#{File.basename(__FILE__)}: '#{self.method_name}' successful!"
  end

  # negative tests to check file parsing & validation
  # email delivery is disabled in development, so this just ensures that bad files are removed after parse failure
  test 'admin: validation: file parsing' do
    puts "#{File.basename(__FILE__)}: '#{self.method_name}'"

    # log in first
    @driver.get @base_url
    login($test_email, $test_email_password)
    @driver.get @base_url + '/studies/new'

    # fill out study form
    study_form = @driver.find_element(:id, 'new_study')
    study_form.find_element(:id, 'study_name').send_keys("Error Messaging Test Study #{$random_seed}")
    # save study
    save_study = @driver.find_element(:id, 'save-study')
    save_study.click

    # upload bad expression matrix
    close_modal('message_modal')
    exp_form = @driver.find_element(:class, 'new-expression-form')
    species_dropdown = exp_form.find_element(:id, 'study_file_taxon_id')
    opts = species_dropdown.find_elements(:tag_name, 'option')
    available_species = opts.delete_if {|opt| opt['value'] == ''}
    if available_species.any?
      species_dropdown.send_keys(available_species.sample.text)
    end
    upload_expression = exp_form.find_element(:id, 'upload-expression')
    upload_expression.send_keys(@test_data_path + 'expression_matrix_example_bad.txt')
    wait_for_render(:id, 'start-file-upload')
    upload_btn = @driver.find_element(:id, 'start-file-upload')
    sleep(0.5)
    upload_btn.click
    # close modal
    close_modal('upload-success-modal')

    # upload an expression matrix in R export format (no value at 0,0 in matrix)
    new_expression = @driver.find_element(:class, 'add-expression')
    new_expression.click
    scroll_to(:bottom)
    exp_2_form = @driver.find_element(:class, 'new-expression-form')
    species_dropdown = exp_2_form.find_element(:id, 'study_file_taxon_id')
    opts = species_dropdown.find_elements(:tag_name, 'option')
    available_species = opts.delete_if {|opt| opt['value'] == ''}
    if available_species.any?
      species_dropdown.send_keys(available_species.sample.text)
    end
    upload_expression = exp_2_form.find_element(:id, 'upload-expression')
    upload_expression.send_keys(@test_data_path + 'R_format_text.txt')
    wait_for_render(:id, 'start-file-upload')
    upload_btn = @driver.find_element(:id, 'start-file-upload')
    sleep(0.5)
    upload_btn.click
    # close modal
    close_modal('upload-success-modal')
    # assert that we cannot delete the newly uploaded file
    exp_form = @driver.find_elements(:class, 'initialize_expression_form').last
    delete_btn = exp_form.find_element(:class, 'disabled-delete')
    assert !delete_btn.nil?, 'Did not find disabled delete button for newly uploaded file'
    assert delete_btn['disabled'] == 'true', "Delete button is not correctly disabled, expected disabled == 'true' but found #{delete_btn['disabled']}"
    next_btn = @driver.find_element(:id, 'next-btn')
    next_btn.click

    # upload bad metadata assignments
    wait_for_render(:id, 'metadata_form')
    upload_assignments = @driver.find_element(:id, 'upload-metadata')
    upload_assignments.send_keys(@test_data_path + 'metadata_bad.txt')
    wait_for_render(:id, 'start-file-upload')
    upload_btn = @driver.find_element(:id, 'start-file-upload')
    sleep(0.5)
    upload_btn.click
    # close modal
    close_modal('upload-success-modal')

    # upload bad cluster coordinates
    upload_clusters = @driver.find_element(:class, 'upload-clusters')
    upload_clusters.send_keys(@test_data_path + 'cluster_bad.txt')
    wait_for_render(:id, 'start-file-upload')
    upload_btn = @driver.find_element(:id, 'start-file-upload')
    sleep(0.5)
    upload_btn.click
    # close modal
    close_modal('upload-success-modal')

    # upload bad marker gene list
    scroll_to(:top)
    gene_list_tab = @driver.find_element(:id, 'initialize_marker_genes_form_nav')
    gene_list_tab.click
    marker_form = @driver.find_element(:class, 'initialize_marker_genes_form')
    marker_file_name = marker_form.find_element(:id, 'study_file_name')
    marker_file_name.send_keys('Test Gene List')
    upload_markers = @driver.find_element(:class, 'upload-marker-genes')
    upload_markers.send_keys(@test_data_path + 'marker_1_gene_list_bad.txt')
    wait_for_render(:id, 'start-file-upload')
    upload_btn = @driver.find_element(:id, 'start-file-upload')
    sleep(0.5)
    upload_btn.click
    # close modal
    close_modal('upload-success-modal')
    # wait for a 2 minutes to allow parses to fail fully
    sleep(120)

    # assert parses all failed and delete study
    @driver.get(@base_url + '/studies')
    wait_until_page_loads(@base_url + '/studies')
    study_file_count = @driver.find_element(:id, "error-messaging-test-study-#{$random_seed}-study-file-count")
    assert study_file_count.text == '1', "found incorrect number of study files; expected 1 and found #{study_file_count.text}"
    @driver.find_element(:class, "error-messaging-test-study-#{$random_seed}-delete").click
    accept_alert
    close_modal('message_modal')
    puts "#{File.basename(__FILE__)}: '#{self.method_name}' successful!"
  end

  # test to verify deleting files removes them from gcs buckets
  test 'admin: validation: delete study file' do
    puts "#{File.basename(__FILE__)}: '#{self.method_name}'"

    @driver.get @base_url
    login($test_email, $test_email_password)
    path = @base_url + '/studies'
    @driver.get path

    add_files = @driver.find_element(:class, "test-study-#{$random_seed}-upload")
    add_files.click
    misc_tab = @driver.find_element(:id, 'initialize_misc_form_nav')
    misc_tab.click

    # test abort functionality first
    add_misc = @driver.find_element(:class, 'add-misc')
    add_misc.click
    new_misc_form = @driver.find_element(:class, 'new-misc-form')
    upload_doc = new_misc_form.find_element(:class, 'upload-misc')
    upload_doc.send_keys(@test_data_path + 'README.txt')
    wait_for_render(:id, 'start-file-upload')
    cancel = @driver.find_element(:class, 'cancel')
    cancel.click
    sleep(3)
    close_modal('study-file-notices')

    # delete file from test study
    form = @driver.find_element(:class, 'initialize_misc_form')
    delete = form.find_element(:class, 'delete-file')
    delete.click
    accept_alert

    # wait a few seconds to allow delete call to propogate all the way to FireCloud after confirmation modal
    close_modal('study-file-notices')
    sleep(3)

    @driver.get path
    files = @driver.find_element(:id, "test-study-#{$random_seed}-study-file-count")
    assert files.text == '9', "did not find correct number of files, expected 9 but found #{files.text}"

    # verify deletion in google
    show_study = @driver.find_element(:class, "test-study-#{$random_seed}-show")
    show_study.click
    gcs_link = @driver.find_element(:id, 'gcs-link')
    gcs_link.click
    @driver.switch_to.window(@driver.window_handles.last)
    sleep(1)
    # select the correct user
    user_link = @driver.find_element(:xpath, "//div[@data-email='#{$test_email}']")
    user_link.click
    table = @driver.find_element(:id, 'p6n-storage-objects-table')
    table_body = table.find_element(:tag_name, 'tbody')
    files = table_body.find_elements(:tag_name, 'tr')
    assert files.size == 9, "did not find correct number of files, expected 9 but found #{files.size}"
    puts "#{File.basename(__FILE__)}: '#{self.method_name}' successful!"
  end

  # test uniqueness constraints on firecloud workspace names
  # this depends on the "development-sync-test-study" workspace being present that is used later for testing sync functionality
  test 'admin: validation: prevent duplicate firecloud workspace' do
    puts "#{File.basename(__FILE__)}: '#{self.method_name}'"

    # log in first
    @driver.get @base_url
    login($test_email, $test_email_password)
    @driver.get @base_url + '/studies/new'

    # fill out study form
    study_form = @driver.find_element(:id, 'new_study')
    study_form.find_element(:id, 'study_name').send_keys('Sync Test Study')
    # save study
    save_study = @driver.find_element(:id, 'save-study')
    save_study.click

    wait_for_render(:id, 'study-errors-block')
    error_message = @driver.find_element(:id, 'study_error_firecloud_workspace')
    assert error_message.text == 'Firecloud workspace - there is already an existing workspace using this name. Please choose another name for your study.'

    # verify that workspace is still there
    firecloud_url = "https://app.terra.bio/#workspaces/single-cell-portal-#{$env}/sync-test-study"
    open_new_page(firecloud_url)
    accept_firecloud_tos
    completed = @driver.find_elements(:class, 'fa-pen')
    assert completed.size >= 1, "did not find workspace - may have been deleted; please check #{firecloud_url}"

    puts "#{File.basename(__FILE__)}: '#{self.method_name}' successful!"
  end

  # prevent users from editing firecloud project/workspace fields on existing studies
  test 'admin: validation: prevent editing study firecloud identifiers' do
    puts "#{File.basename(__FILE__)}: '#{self.method_name}'"

    # log in first
    @driver.get @base_url
    login($test_email, $test_email_password)
    @driver.get @base_url + '/studies'

    edit_btn = @driver.find_element(:class, "test-study-#{$random_seed}-edit")
    edit_btn.click
    wait_for_render(:class, 'study-form')

    # find firecloud project/workspace fields and assert inability to change
    firecloud_project = @driver.find_element(:id, 'study_firecloud_project')
    firecloud_workspace = @driver.find_element(:id, 'study_firecloud_workspace')
    assert firecloud_project['readonly'] == 'true', 'firecloud project form field is not readonly'
    assert firecloud_workspace['readonly'] == 'true', 'firecloud workspace form field is not readonly'
    current_project = firecloud_project['value']
    current_workspace = firecloud_workspace['value']
    bad_value = 'foo'
    firecloud_project.send_keys(bad_value)
    firecloud_workspace.send_keys(bad_value)
    assert firecloud_project['value'] == current_project, "project name allowed change; expected #{current_project} but found #{firecloud_project['value']}"
    assert firecloud_workspace['value'] == current_workspace, "workspace name allowed change; expected #{current_workspace} but found #{firecloud_workspace['value']}"

    puts "#{File.basename(__FILE__)}: '#{self.method_name}' successful!"
  end

  # check visibility & edit restrictions as well as share access
  # will also verify FireCloud ACL settings on shares
  test 'admin: sharing: view and edit permission' do
    puts "#{File.basename(__FILE__)}: '#{self.method_name}'"

    # check view visibility for unauthenticated users
    path = @base_url + "/study/private-study-#{$random_seed}"
    @driver.get path
    assert @driver.current_url == @base_url + "/users/sign_in", 'did not redirect to sign-in page'
    assert element_present?(:id, 'message_modal'), 'did not find alert modal'
    close_modal('message_modal')

    login($test_email, $test_email_password)
    @driver.get @base_url + '/studies'

    # get path info
    edit = @driver.find_element(:class, "private-study-#{$random_seed}-edit")
    edit.click
    # wait a few seconds for page to load before getting url
    sleep(2)
    private_study_id = @driver.current_url.split('/')[5]
    @driver.get @base_url + '/studies'
    edit = @driver.find_element(:class, "test-study-#{$random_seed}-edit")
    edit.click
    # wait a few seconds for page to load before getting url
    sleep(2)
    share_study_id = @driver.current_url.split('/')[5]

    # logout
    logout_from_portal

    # login as share user
    login_as_other($share_email, $share_email_password)

    # view study
    path = @base_url + "/study/private-study-#{$random_seed}"
    @driver.get path
    assert @driver.current_url == @base_url, 'did not redirect'
    assert element_present?(:id, 'message_modal'), 'did not find alert modal'
    close_modal('message_modal')
    # check public visibility when logged in
    path = @base_url + "/study/gzip-parse-#{$random_seed}"
    @driver.get path
    study_accession = extract_accession_from_url(@driver.current_url)
    loaded_path = @base_url + "/study/#{study_accession}/gzip-parse-#{$random_seed}"
    assert @driver.current_url == loaded_path, 'did not load public study without share'

    # edit study
    edit_path = @base_url + '/studies/' + private_study_id + '/edit'
    @driver.get edit_path
    assert @driver.current_url == @base_url + '/studies', 'did not redirect'
    assert element_present?(:id, 'message_modal'), 'did not find alert modal'
    close_modal('message_modal')

    # test share
    share_view_path = @base_url + "/study/test-study-#{$random_seed}"
    @driver.get share_view_path
    study_accession = extract_accession_from_url(@driver.current_url)
    loaded_view_share_path = @base_url + "/study/#{study_accession}/test-study-#{$random_seed}"
    assert @driver.current_url == loaded_view_share_path, 'did not load share study view'
    share_edit_path = @base_url + '/studies/' + share_study_id + '/edit'
    @driver.get share_edit_path
    assert @driver.current_url == share_edit_path, 'did not load share study edit'

    # test uploading a file
    upload_path = @base_url + '/studies/' + share_study_id + '/upload'
    @driver.get upload_path
    misc_tab = @driver.find_element(:id, 'initialize_misc_form_nav')
    misc_tab.click

    upload_doc = @driver.find_element(:class, 'upload-misc')
    upload_doc.send_keys(@test_data_path + 'README.txt')
    upload_btn = @driver.find_element(:id, 'start-file-upload')
    sleep(0.5)
    upload_btn.click
    close_modal('upload-success-modal')

    # verify upload has completed and is in FireCloud bucket
    @driver.get @base_url + '/studies/'
    file_count = @driver.find_element(:id, "test-study-#{$random_seed}-study-file-count")
    assert file_count.text == '10', "did not find correct number of files, expected 10 but found #{file_count.text}"
    show_study = @driver.find_element(:class, "test-study-#{$random_seed}-show")
    show_study.click
    # verify gcs bucket upload
    gcs_link = @driver.find_element(:id, 'gcs-link')
    gcs_link.click
    @driver.switch_to.window(@driver.window_handles.last)
    sleep(1)
    # select the correct user
    user_link = @driver.find_element(:xpath, "//div[@data-email='#{$share_email}']")
    user_link.click
    table = @driver.find_element(:id, 'p6n-storage-objects-table')
    table_body = table.find_element(:tag_name, 'tbody')
    files = table_body.find_elements(:tag_name, 'tr')
    assert files.size == 10, "did not find correct number of files, expected 9 but found #{files.size}"
    puts "#{File.basename(__FILE__)}: '#{self.method_name}' successful!"
  end

  # test reviewer functionality
  test 'admin: sharing: reviewer permission' do
    puts "#{File.basename(__FILE__)}: '#{self.method_name}'"

    @driver.get @base_url
    login($test_email, $test_email_password)
    @driver.get @base_url + '/studies'

    edit = @driver.find_element(:class, "private-study-#{$random_seed}-edit")
    edit.click
    wait_for_render(:class, 'study-form')
    study_form = @driver.find_element(:class, 'study-form')
    share = study_form.find_element(:id, 'add-study-share')
    @wait.until {share.displayed?}
    share.click
    share_email = study_form.find_element(:class, 'share-email')
    share_email.send_keys($share_email)
    share_permission = study_form.find_element(:class, 'share-permission')
    share_permission.send_keys('Reviewer')
    save_study = @driver.find_element(:id, 'save-study')
    save_study.click
    close_modal('message_modal')
    # now confirm reviewer share
    logout_from_portal
    login_as_other($share_email, $share_email_password)
    # make sure study shows up in list of 'My studies'
    path = @base_url + "/studies"
    @driver.get path
    wait_for_render(:id, 'studies')
    assert element_present?(:id, "private-study-#{$random_seed}-view-live-link"), "Did not find link to view private study"
    private_study_link = @driver.find_element(:id, "private-study-#{$random_seed}-view-live-link")
    private_study_link.click
    assert element_present?(:class, 'study-lead'), 'Did not correctly load study page'

    # make sure download tab is properly disabled and no files can be downloaded
    download_tab = @driver.find_element(:id, 'study-download-nav')
    assert download_tab['class'].include?('disabled'), "Download tab was not properly disabled: #{download_tab['class']}"
    # try bypassing download with a direct call to file we uploaded earlier
    study_accession = extract_accession_from_url(@driver.current_url)
    direct_link = @base_url + "/data/public/#{study_accession}/private-study-#{$random_seed}?filename=expression_matrix_example.txt"
    @driver.get direct_link
    alert_content = @driver.find_element(:id, 'alert-content')
    assert alert_content.text == 'You do not have permission to perform that action.', 'download was not successfully blocked'

    puts "#{File.basename(__FILE__)}: '#{self.method_name}' successful!"
  end

  ##
  ## SYNCHRONIZATION TESTS
  ## Validates that 'sync' functionality is working correctly (creating a study from an existing FireCloud workspace)
  ##

  # this test depends on a workspace already existing in FireCloud called development-sync-test
  # if this study has been deleted, this test will fail until the workspace is re-created with at least
  # 3 default files for expression, metadata, one cluster, and one fastq file (using the test data from test/test_data)
  test 'admin: create-study: sync-study: bulk: existing workspace' do
    puts "#{File.basename(__FILE__)}: '#{self.method_name}'"

    # log in first
    @driver.get @base_url
    login($test_email, $test_email_password)
    @driver.get @base_url + '/studies/new'

    # create a new study using an existing workspace, also generate a random name to validate that workspace name
    # and study name can be different
    random_name = "Sync Test #{$random_seed}"
    study_form = @driver.find_element(:id, 'new_study')
    study_form.find_element(:id, 'study_name').send_keys(random_name)
    study_form.find_element(:id, 'study_use_existing_workspace').send_keys('Yes')
    study_form.find_element(:id, 'study_firecloud_workspace').send_keys("sync-test-study")
    share = @driver.find_element(:id, 'add-study-share')
    @wait.until {share.displayed?}
    share.click
    share_email = study_form.find_element(:class, 'share-email')
    share_email.send_keys($share_email)

    # save study
    save_study = @driver.find_element(:id, 'save-study')
    save_study.click
    @wait.until {element_present?(:id, 'unsynced-study-files')}
    close_modal('message_modal')

    # sync each file
    study_file_forms = @driver.find_elements(:class, 'unsynced-study-file')
    study_file_forms.each do |form|
      filename = form.find_element(:id, 'study_file_name')['value']
      file_type = form.find_element(:id, 'study_file_file_type')
      case filename
        when 'cluster_example.txt'
          file_type.send_keys('Cluster')
        when 'subfolder/expression_matrix_example.txt'
          file_type.send_keys('Expression Matrix')
          species_dropdown = form.find_element(:id, 'study_file_taxon_id')
          opts = species_dropdown.find_elements(:tag_name, 'option')
          available_species = opts.delete_if {|opt| opt['value'] == ''}
          if available_species.any?
            species_dropdown.send_keys(available_species.sample.text)
          end
        when 'metadata_example.txt'
          file_type.send_keys('Metadata')
        else
          file_type.send_keys('Other')
      end
      sync_button = form.find_element(:class, 'save-study-file')
      sync_button.click
      close_modal('sync-notice-modal')
    end

    # sync directory listings
    directory_forms = @driver.find_elements(:class, 'unsynced-directory-listing')
    directory_forms.each do |form|
      file_type = form.find_element(:id, 'directory_listing_file_type')
      # specify a species for fastq data
      if file_type['value'] == 'fastq'
        species_dropdown = form.find_element(:id, 'directory_listing_taxon_id')
        opts = species_dropdown.find_elements(:tag_name, 'option')
        available_species = opts.delete_if {|opt| opt['value'] == ''}
        if available_species.any?
          taxon = available_species.select {|s| !s.text != 'human'}.sample.text
          species_dropdown.send_keys(taxon)
        end
      end

      sync_button = form.find_element(:class, 'save-directory-listing')
      sync_button.click
      close_modal('sync-notice-modal')
    end

    # now assert that forms were re-rendered in synced data panel
    sync_panel = @driver.find_element(:id, 'synced-data-panel-toggle')
    sync_panel.click
    # wait a second for panel to open
    sleep(1)
    synced_files_div = @driver.find_element(:id, 'synced-study-files')
    synced_files = synced_files_div.find_elements(:tag_name, 'form')
    assert synced_files.size == study_file_forms.size, "did not find correct number of synced files, expected #{study_file_forms.size} but found #{synced_files.size}"

    synced_dirs_div = @driver.find_element(:id, 'synced-directory-listings')
    synced_dirs = synced_dirs_div.find_elements(:tag_name, 'form')
    assert synced_dirs.size == directory_forms.size, "did not find correct number of synced files, expected #{directory_forms.size} but found #{synced_dirs.size}"

    updated_files = {}
    # now use synced data forms to update entries and keep track of changes for comparison later
    synced_files.each do |sync_form|
      file_type = sync_form.find_element(:id, 'study_file_file_type')[:value]
      name = sync_form.find_element(:id, 'study_file_name')[:value]
      description = "Description for #{file_type}"
      description_field = sync_form.find_element(:id, 'study_file_description')
      description_field.send_keys(description)
      updated_files["#{sync_form[:id]}"] = {
          name: name,
          file_type: file_type,
          description: description,
          parsed: file_type != 'Other'
      }
      sync_button = sync_form.find_element(:class, 'save-study-file')
      sync_button.click
      close_modal('sync-notice-modal')
    end

    # update directory listings too
    updated_dirs = {}
    synced_dirs.each do |sync_form|
      name = sync_form.find_element(:id, 'directory_listing_name')[:value]
      description = "Description for #{name}"
      description_field = sync_form.find_element(:id, 'directory_listing_description')
      description_field.send_keys(description)
      updated_dirs["#{sync_form[:id]}"] = {
          description: description,
          file_type: sync_form.find_element(:id, 'directory_listing_file_type')[:value]
      }
      sync_button = sync_form.find_element(:class, 'save-directory-listing')
      sync_button.click
      close_modal('sync-notice-modal')
    end

    # lastly, check info page to make sure everything did in fact parse and complete
    studies_path = @base_url + '/studies'
    @driver.get studies_path
    wait_until_page_loads(studies_path)

    show_button = @driver.find_element(:class, "sync-test-#{$random_seed}-show")
    show_button.click
    @wait.until {element_present?(:id, 'info-panel')}

    # assert number of files using the count badges (faster than counting table rows)
    study_file_count = @driver.find_element(:id, 'study-file-count').text.to_i
    primary_data_count = @driver.find_element(:id, 'primary-data-count').text.to_i
    other_data_count = @driver.find_element(:id, 'other-data-count').text.to_i
    assert study_file_count == study_file_forms.size, "did not find correct number of study files, expected #{study_file_forms.size} but found #{study_file_count}"
    assert primary_data_count == 1, "did not find correct number of primary data files, expected 1 but found #{primary_data_count}"
    assert other_data_count == 19, "did not find correct number of other data files, expected 19 but found #{primary_data_count}"

    # Parse should take less than 2 minutes
    i = 0
    parsed_files = @driver.find_elements(:class, 'study-file-parsed').map {|el| el['data-parsed'] == 'true'}.uniq
    while parsed_files.size > 1 && i < 12
      i += 1
      sleep(10)
      @driver.get @driver.current_url
      parsed_files = @driver.find_elements(:class, 'study-file-parsed').map {|el| el['data-parsed'] == 'true'}.uniq
    end

    # make sure edits saved by going through updated list of synced files and comparing values
    updated_files.each do |id, values|
      study_file_table_row = @driver.find_element(:id, id)
      entry_name = study_file_table_row.find_element(:class, 'study-file-name').text
      entry_file_type = study_file_table_row.find_element(:class, 'study-file-file-type').text
      entry_description = study_file_table_row.find_element(:class, 'study-file-description').text
      entry_parsed = study_file_table_row.find_element(:class, 'study-file-parsed')['data-parsed'] == 'true'
      assert values[:name] == entry_name, "study file entry #{id} name incorrect, expected #{values[:name]} but found #{entry_name}"
      assert values[:file_type] == entry_file_type, "study file entry #{id} file type incorrect, expected #{values[:file_type]} but found #{entry_file_type}"
      assert values[:description] == entry_description, "study file entry #{id} description incorrect, expected #{values[:description]} but found #{entry_description}"
      assert values[:parsed] == entry_parsed, "study file entry #{id} parse incorrect, expected #{values[:parsed]} but found #{entry_parsed}"
    end

    # now check directory listings datatables - we only need to match the first found row as all rows will have identical descriptions
    updated_dirs.each_value do |values|
      directory_listing_row = @driver.find_element(:class, values[:file_type] + '-entry')
      found_description = directory_listing_row.find_element(:class, 'dl-description')
      assert values[:description] == found_description.text, "directory listing description incorrect, expected #{values[:description]} but found #{found_description.text}"
    end

    # assert share was added
    share_email_id = 'study-share-' + $share_email.gsub(/[@.]/, '-')
    assert element_present?(:id, share_email_id), 'did not find proper share entry'
    share_row = @driver.find_element(:id, share_email_id)
    shared_email = share_row.find_element(:class, 'share-email').text
    assert shared_email == $share_email, "did not find correct email for share, expected #{$share_email} but found #{shared_email}"
    shared_permission = share_row.find_element(:class, 'share-permission').text.split.first
    assert shared_permission == 'View', "did not find correct share permissions, expected View but found #{shared_permission}"

    # make sure parsing succeeded
    sync_study_path = @base_url + "/study/sync-test-#{$random_seed}"
    @driver.get(sync_study_path)
    study_accession = extract_accession_from_url(@driver.current_url)
    loaded_sync_study_path = @base_url + "/study/#{study_accession}/sync-test-#{$random_seed}"
    wait_until_page_loads(loaded_sync_study_path)
    open_ui_tab('study-visualize')

    assert element_present?(:class, 'study-lead'), 'could not find study title'
    assert element_present?(:id, 'cluster-plot'), 'could not find study cluster plot'

    # wait until cluster finishes rendering
    @wait.until {wait_for_plotly_render('#cluster-plot', 'rendered')}
    rendered = @driver.execute_script("return $('#cluster-plot').data('rendered')")
    assert rendered, "cluster plot did not finish rendering, expected true but found #{rendered}"

    # search for a gene
    gene = @genes.sample
    search_box = @driver.find_element(:id, 'search_genes')
    search_box.send_keys(gene)
    search_genes = @driver.find_element(:id, 'perform-gene-search')
    search_genes.click

    @wait.until {wait_for_plotly_render('#expression-plots', 'box-rendered')}
    violin_rendered = @driver.execute_script("return $('#expression-plots').data('box-rendered')")
    assert violin_rendered, "violin plot did not finish rendering, expected true but found #{violin_rendered}"
    scatter_rendered = @driver.execute_script("return $('#expression-plots').data('scatter-rendered')")
    assert scatter_rendered, "scatter plot did not finish rendering, expected true but found #{scatter_rendered}"
    reference_rendered = @driver.execute_script("return $('#expression-plots').data('reference-rendered')")
    assert reference_rendered, "reference plot did not finish rendering, expected true but found #{reference_rendered}"

    # now test removing items
    @driver.get(@base_url + '/studies')
    sync_button_class = random_name.split.map(&:downcase).join('-') + '-sync'
    sync_button = @driver.find_element(:class, sync_button_class)
    sync_button.click
    @wait.until {element_present?(:id, 'synced-study-files')}

    sync_panel = @driver.find_element(:id, 'synced-data-panel-toggle')
    sync_panel.click
    sleep(1)
    synced_files = @driver.find_elements(:class, 'synced-study-file')
    synced_directory_listing = @driver.find_element(:class, 'synced-directory-listing')

    # delete random file
    file_to_delete = synced_files.sample
    delete_file_btn = file_to_delete.find_element(:class, 'delete-study-file')
    delete_file_btn.click
    accept_alert
    close_modal('sync-notice-modal')

    # delete directory listing
    delete_dir_btn = synced_directory_listing.find_element(:class, 'delete-directory-listing')
    delete_dir_btn.click
    accept_alert
    close_modal('sync-notice-modal')
    # give DelayedJob one second to fire the DeleteQueueJob to remove the deleted entries
    sleep(1)

    # confirm files were removed
    @driver.get studies_path
    wait_until_page_loads(studies_path)
    study_file_count = @driver.find_element(:id, "sync-test-#{$random_seed}-study-file-count").text.to_i
    assert study_file_count == 2, "did not remove files, expected 2 but found #{study_file_count}"

    # remove share and resync
    edit_button = @driver.find_element(:class, "sync-test-#{$random_seed}-edit")
    edit_button.click
    wait_for_render(:class, 'study-share-form')
    # we need an extra sleep here to allow the javascript handlers to attach so that the remove_nested_fields event will fire
    sleep(0.5)
    share_id = $share_email.gsub(/[@\.]/, '-') + '-share-form'
    share_form = @driver.find_element(:id, share_id)
    remove_share = share_form.find_element(:class, 'remove_nested_fields')
    remove_share.click
    accept_alert
    # let the form remove from the page
    sleep (0.25)
    save_study = @driver.find_element(:id, 'save-study')
    save_study.click
    close_modal('message_modal')
    sync_button = @driver.find_element(:class, "sync-test-#{$random_seed}-sync")
    sync_button.click
    wait_for_render(:id, 'synced-data-panel-toggle')

    # now confirm share was removed at FireCloud level
    logout_from_portal

    # now login as share user and check workspace
    login_as_other($share_email, $share_email_password)
    firecloud_workspace = "https://app.terra.bio/#workspaces/single-cell-portal-#{$env}/sync-test-#{$random_seed}"
    @driver.get firecloud_workspace
    accept_firecloud_tos
    assert !element_present?(:class, 'fa-pen'), 'did not revoke access - study workspace still loads'

    puts "#{File.basename(__FILE__)}: '#{self.method_name}' successful!"
  end

  # test validation of not allowing studies with an authorizationDomain attribute
  # this test requires a workspace with the name of "development-authorization-domain-test-study" that is restricted
  # by an authorization domain user group.  The portal service account must be a member of this group in order to pass.
  test 'admin: sync-study: restricted workspace' do
    puts "#{File.basename(__FILE__)}: '#{self.method_name}'"

    # log in first
    @driver.get @base_url
    login($test_email, $test_email_password)
    @driver.get @base_url + '/studies/new'

    # attempt to create a study using a workspace with a restricted authorizationDomain
    random_name = "Restricted Sync Test #{$random_seed}"
    study_form = @driver.find_element(:id, 'new_study')
    study_form.find_element(:id, 'study_name').send_keys(random_name)
    study_form.find_element(:id, 'study_use_existing_workspace').send_keys('Yes')
    study_form.find_element(:id, 'study_firecloud_workspace').send_keys("authorization-domain-test-study")

    save_study = @driver.find_element(:id, 'save-study')
    save_study.click
    wait_for_render(:id, 'study-errors-block')
    error_message = @driver.find_element(:id, 'study-errors-block').find_element(:tag_name, 'li').text
    assert error_message.include?('The workspace you provided is restricted.'), "Did not find correct error message, expected 'The workspace you provided is restricted.' but found #{error_message}"

    puts "#{File.basename(__FILE__)}: '#{self.method_name}' successful!"
  end

  ##
  ## BRANDING TESTS
  ##

  test 'admin: branding-groups: create' do
    puts "#{File.basename(__FILE__)}: '#{self.method_name}'"

    @driver.get @base_url
    login($test_email, $test_email_password)
    @driver.get @base_url + '/branding_groups'

    new_branding_btn = @driver.find_element(:id, 'new-branding-group')
    new_branding_btn.click
    wait_for_render(:class, 'branding-group-form')

    form = @driver.find_element(:class, 'branding-group-form')
    name = "Branding Group #{$random_seed}"
    tag_line = "This is the tag line."
    bg_color = '#00ffff'
    font_family = 'Tahoma, sans-serif'
    font_color = '#666666'
    splash_image = @test_data_path + '/branding_groups/SCP-logo-invert.png'
    banner_image = @test_data_path + '/branding_groups/SCP-Header-resize-invert.png'
    footer_image = @test_data_path + '/branding_groups/broad-logo-white-invert.png'

    # we have to set the color value via JS as webdriver can't interact with the native OS colorpicker dialog
    @driver.execute_script("$('#branding_group_background_color').val('#{bg_color}');")
    @driver.execute_script("$('#branding_group_font_color').val('#{font_color}');")

    # the rest behave normally
    name_field = form.find_element(:id, 'branding_group_name')
    name_field.send_keys(name)
    tag_line_field = form.find_element(:id, 'branding_group_tag_line')
    tag_line_field.send_keys(tag_line)
    font_family_field = form.find_element(:id, 'branding_group_font_family')
    font_family_field.send_keys(font_family)
    splash_image_field = form.find_element(:id, 'branding_group_splash_image')
    splash_image_field.send_keys(splash_image)
    banner_image_field = form.find_element(:id, 'branding_group_banner_image')
    banner_image_field.send_keys(banner_image)
    footer_image_field = form.find_element(:id, 'branding_group_footer_image')
    footer_image_field.send_keys(footer_image)
    user_field = form.find_element(:id, 'branding_group_user_id')
    user_field.send_keys($test_email)
    save_btn = form.find_element(:id, 'save-branding-group')
    save_btn.click
    wait_for_render(:id, 'scp-footer')

    saved_name = @driver.find_element(:id, 'branding_group_name').text
    saved_tag_line = @driver.find_element(:id, 'branding_group_tag_line').text
    saved_bg_color = @driver.find_element(:id, 'branding_group_background_color').text
    saved_font_family = @driver.find_element(:id, 'branding_group_font_family').text
    saved_font_color = @driver.find_element(:id, 'branding_group_font_color').text
    saved_splash_image = @driver.find_element(:id, 'branding_group_splash_image').text
    saved_banner_image = @driver.find_element(:id, 'branding_group_banner_image').text
    saved_footer_image = @driver.find_element(:id, 'branding_group_footer_image').text

    assert saved_name == name, "Name did not save correctly, expected '#{name}' but found '#{saved_name}'"
    assert saved_tag_line == tag_line, "tag_line did not save correctly, expected '#{tag_line}' but found '#{saved_tag_line}'"
    assert saved_bg_color == bg_color, "bg_color did not save correctly, expected '#{bg_color}' but found '#{saved_bg_color}'"
    assert saved_font_family == font_family, "font_family did not save correctly, expected '#{font_family}' but found '#{saved_font_family}'"
    assert saved_font_color == font_color, "font_color did not save correctly, expected '#{font_color}' but found '#{saved_font_color}'"
    assert saved_splash_image == 'SCP-logo-invert.png', "Splash image did not save correctly, expected 'SCP-logo-invert.png' but found '#{saved_splash_image}'"
    assert saved_banner_image == 'SCP-Header-resize-invert.png', "Banner image did not save correctly, expected 'SCP-Header-resize-invert.png' but found '#{saved_banner_image}'"
    assert saved_footer_image == 'broad-logo-white-invert.png', "Footer image did not save correctly, expected 'broad-logo-white-invert.png' but found '#{saved_footer_image}'"

    @driver.get @base_url + '/studies'
    wait_for_render(:id, 'studies')

    # add test study
    edit_test = @driver.find_element(:class, "test-study-#{$random_seed}-edit")
    edit_test.click
    wait_for_render(:class, 'study-form')
    brand_select = @driver.find_element(:id, 'study_branding_group_id')
    brand_select.send_keys(name)
    save_test = @driver.find_element(:id, 'save-study')
    save_test.click
    close_modal('message_modal')

    # add private study
    edit_private = @driver.find_element(:class, "private-study-#{$random_seed}-edit")
    edit_private.click
    wait_for_render(:class, 'study-form')
    brand_select = @driver.find_element(:id, 'study_branding_group_id')
    brand_select.send_keys(name)
    save_private = @driver.find_element(:id, 'save-study')
    save_private.click
    close_modal('message_modal')

    @driver.get @base_url + '/branding_groups'
    wait_for_render(:id, 'branding-groups')
    study_count = @driver.find_element(:class, 'branding-group-study-count')
    assert study_count.text.to_i == 2, "Did not find correct number of studies, expected 2 but found #{study_count.text}"

    puts "#{File.basename(__FILE__)}: '#{self.method_name}' successful!"
  end

  test 'admin: branding-groups: view' do
    puts "#{File.basename(__FILE__)}: '#{self.method_name}'"

    @driver.get @base_url
    login($test_email, $test_email_password)

    profile_menu = @driver.find_element(:id, 'profile-nav')
    profile_menu.click
    brand_id = "branding-group-#{$random_seed}"
    branding_nav = @driver.find_element(:id, brand_id + '-nav')
    branding_nav.click
    loaded = false
    while !loaded
      loaded_brand = @driver.execute_script("return $('body').data('branding-id');")
      if loaded_brand == brand_id
        loaded = true
      else
        sleep(1)
      end
    end

    # now search for studies to make sure scoping is correct
    search_box = @driver.find_element(:id, 'search_terms')
    search_box.send_keys("#{$random_seed}")
    submit = @driver.find_element(:id, 'submit-search')
    submit.click
    studies = @driver.find_elements(:class, 'study-panel').size
    assert studies == 2, "Did not scope search correctly, expected 2 studies but found #{studies}"

    view_link = @driver.find_element(:class, 'view-study-page')
    view_link.click
    wait_for_render(:class, 'study-lead')
    open_ui_tab('study-visualize')

    # assert styles have persisted
    expected_bg = 'rgb(0, 255, 255)'
    expected_font = 'Tahoma, sans-serif'
    bg_color = @driver.execute_script("return $('body').css('background-color');")
    font_family = @driver.execute_script("return $('body').css('font-family');")
    assert bg_color == expected_bg, "Background color is incorrect, expected '#{expected_bg}' but found '#{bg_color}'"
    assert font_family == expected_font, "Background color is incorrect, expected '#{expected_font}' but found '#{font_family}'"
    current_url = @driver.current_url
    assert current_url.include?("scpbr=#{brand_id}"), "Brand URL paramerter is not present: #{current_url}"

    # search for a gene to make sure styles persist
    gene = @genes.sample
    search_box = @driver.find_element(:id, 'search_genes')
    search_box.send_keys(gene)
    search_genes = @driver.find_element(:id, 'perform-gene-search')
    search_genes.click
    @wait.until {wait_for_plotly_render('#expression-plots', 'box-rendered')}

    current_bg_color = @driver.execute_script("return $('body').css('background-color');")
    current_font_family = @driver.execute_script("return $('body').css('font-family');")
    assert current_bg_color == expected_bg, "Background color is incorrect after search, expected '#{expected_bg}' but found '#{current_bg_color}'"
    assert current_font_family == expected_font, "Background color is incorrect after search, expected '#{expected_font}' but found '#{current_font_family}'"

    puts "#{File.basename(__FILE__)}: '#{self.method_name}' successful!"
  end

  test 'admin: branding-groups: delete' do
    puts "#{File.basename(__FILE__)}: '#{self.method_name}'"

    @driver.get @base_url
    login($test_email, $test_email_password)
    @driver.get @base_url + '/branding_groups'

    delete_btn = @driver.find_element(:class, "branding-group-#{$random_seed}-delete")
    delete_btn.click
    accept_alert
    close_modal('message_modal')

    branding_groups = @driver.find_element(:id, 'branding-groups').find_element(:tag_name, 'tbody').find_elements(:tag_name, 'tr').map {|row| row['id']}
    assert !branding_groups.include?("branding-group-#{$random_seed}"), "Branding group did not delete: #{branding_groups}"

    puts "#{File.basename(__FILE__)}: '#{self.method_name}' successful!"
  end

  ##
  ## ANALYSIS CONFIGURATION TESTS
  ##

  test 'admin: analysis-configurations: workflows: add and configure analysis' do
    puts "#{File.basename(__FILE__)}: '#{self.method_name}'"

    @driver.get @base_url
    login($test_email, $test_email_password)
    @driver.get @base_url + '/analysis_configurations/new'

    namespace_field = @driver.find_element(:id, 'analysis_configuration_namespace')
    namespace_field.send_keys('single-cell-portal')
    name_field = @driver.find_element(:id, 'analysis_configuration_name')
    name_field.send_keys('split-cluster')
    snapshot_field = @driver.find_element(:id, 'analysis_configuration_snapshot')
    snapshot_field.send_keys(1)
    config_namespace_field = @driver.find_element(:id, 'analysis_configuration_configuration_namespace')
    config_namespace_field.send_keys('single-cell-portal')
    config_name_field = @driver.find_element(:id, 'analysis_configuration_configuration_name')
    config_name_field.send_keys('split-cluster')
    config_snapshot_field = @driver.find_element(:id, 'analysis_configuration_configuration_snapshot')
    config_snapshot_field.send_keys(2)
    save_btn = @driver.find_element(:id, 'save-analysis-configuration')
    save_btn.click

    # wait for config page to load
    close_modal('message_modal')
    wait_for_render(:id, 'inputs')

    # add external resource
    add_resource = @driver.find_element(:id, 'add-external-resource')
    add_resource.click
    resource_title = @driver.find_element(:class, 'external-resource-title')
    resource_title.send_keys('split-cluster Documentation')
    resource_description = @driver.find_element(:class, 'external-resource-description')
    resource_description.send_keys('Documentation for split-cluster')
    resource_url = @driver.find_element(:class, 'external-resource-url')
    resource_url.send_keys('https://portal.firecloud.org/#methods/single-cell-portal/split-cluster/1')
    save_links = @driver.find_element(:id, 'update-doc-links')
    save_links.click
    close_modal('message_modal')

    # configure analysis input
    input_form = @driver.find_element(:class, 'input-analysis-parameter')
    assoc_model = input_form.find_element(:class, 'associated-model-field')
    assoc_model.send_keys('StudyFile')
    sleep(1) # need to wait for REST call to populate other dropdowns
    model_method = input_form.find_element(class: 'associated_model_method')
    model_method.send_keys('gs_url')
    model_display = input_form.find_element(class: 'associated_model_display_method')
    model_display.send_keys('name')
    add_filter_btn = input_form.find_element(:id, 'add-analysis-parameter-filter')
    add_filter_btn.click
    filter_form = input_form.find_element(:class, 'analysis_parameter_filter_fields')
    filter_attr = filter_form.find_element(:class, 'analysis_parameter_filter_attribute_name')
    filter_attr.send_keys('file_type')
    filter_val = filter_form.find_element(:class, 'analysis_parameter_filter_value')
    filter_val.send_keys('Cluster')
    save_btn = input_form.find_element(:class, 'save-analysis-parameter')
    save_btn.click
    close_modal('generic-update-modal')

    # configure analysis output
    output_nav = @driver.find_element(:id, 'outputs-nav')
    output_nav.click
    @wait.until {element_visible?(:id, 'outputs')}
    output_form = @driver.find_element(:class, 'output-analysis-parameter')
    out_file_type = output_form.find_element(:id, 'analysis_parameter_output_file_type')
    out_file_type.send_keys('Cluster')
    add_assoc = output_form.find_element(:id, 'add-analysis-output-association')
    add_assoc.click
    assoc_form = output_form.find_element(:class, 'analysis_output_association_fields')
    attr_dropdown = assoc_form.find_element(:class, 'analysis_output_association_attribute_name')
    attr_dropdown.send_keys('description')
    attr_value = assoc_form.find_element(:class, 'analysis_output_association_attribute_value')
    attr_value.send_keys("Description set from run #{$random_seed}")
    save_btn = output_form.find_element(:class, 'save-analysis-parameter')
    save_btn.click
    close_modal('generic-update-modal')

    @driver.get @base_url + '/analysis_configurations'
    wait_for_render(:id, 'analysis-configurations')
    configs = @driver.find_element(:id, 'analysis-configurations')
    split_cluster_tr = configs.find_element(:id, 'single-cell-portal-split-cluster-1')
    config_identifier = split_cluster_tr.find_element(:class, 'analysis-config-identifer')
    assert config_identifier.text == 'single-cell-portal/split-cluster/1',
           "Did not find correct identifier name, expected 'single-cell-portal/split-cluster/1' but found #{config_identifier.text}"
    expected_synopsis = 'Single Cell Portal testing WDL to split a cluster on annotations'
    config_synopsis = split_cluster_tr.find_element(:class, 'analysis-config-synopsis')
    assert config_synopsis.text == expected_synopsis,
           "Did not find correct identifier name, expected '#{expected_synopsis}' but found #{config_synopsis.text}"

    puts "#{File.basename(__FILE__)}: '#{self.method_name}' successful!"
  end

  ##
  ## USER PROFILE TESTS
  ## Setting email preferences, etc
  ##

  test 'user-profiles: update email preferences' do
    puts "#{File.basename(__FILE__)}: '#{self.method_name}'"

    @driver.get @base_url
    login($test_email, $test_email_password)

    # open profile page
    profile = @driver.find_element(:id, 'profile-nav')
    profile.click
    profile_link = @driver.find_element(:id, 'my-profile')
    profile_link.click
    wait_for_render(:id, 'profile-header')

    # toggle admin emails
    admin_toggle = @driver.find_element(:id, 'toggle-admin-emails')
    admin_toggle.click
    @wait.until {admin_toggle.text == 'Off'}
    toggle_text = admin_toggle.text
    assert toggle_text == 'Off', "Did not properly turn off admin emails (text is still #{toggle_text})"
    admin_toggle.click
    @wait.until {admin_toggle.text == 'On'}
    new_toggle_text = admin_toggle.text
    assert new_toggle_text == 'On', "Did not properly turn on admin emails (text is still #{new_toggle_text})"

    # toggle study/share notification
    study_notifier_toggle = @driver.find_element(:class, 'toggle-study-subscription')
    study_notifier_toggle.click
    @wait.until {@driver.find_element(:class, 'toggle-study-subscription').text == 'Off'}
    study_text = study_notifier_toggle.text
    assert study_text == 'Off', "Did not properly turn off study notification (text is still #{study_text})"
    study_notifier_toggle.click
    @wait.until {@driver.find_element(:class, 'toggle-study-subscription').text == 'On'}
    new_study_text = study_notifier_toggle.text
    assert new_study_text == 'On', "Did not properly turn on study notification (text is still #{new_study_text})"

    puts "#{File.basename(__FILE__)}: '#{self.method_name}' successful!"
  end

  # update a user's FireCloud profile from the user profile section
  test 'user-profiles: update firecloud profile' do
    puts "#{File.basename(__FILE__)}: '#{self.method_name}'"

    @driver.get @base_url
    login($test_email, $test_email_password)

    # open profile page
    profile = @driver.find_element(:id, 'profile-nav')
    profile.click
    profile_link = @driver.find_element(:id, 'my-profile')
    profile_link.click
    wait_for_render(:id, 'profile-header')

    open_ui_tab('profile-firecloud')

    job_title_field = @driver.find_element(:id, 'fire_cloud_profile_title')
    job_title_field.clear
    new_title = "Random Title #{$random_seed}"
    job_title_field.send_keys(new_title)
    update_btn = @driver.find_element(:id, 'update-user-firecloud-profile')
    update_btn.click
    wait_for_modal_open('message_modal')

    # reload page to confirm save
    @driver.get @driver.current_url
    wait_for_render(:id, 'profile-header')
    open_ui_tab('profile-firecloud')

    job_title = @driver.find_element(:id, 'fire_cloud_profile_title')['value']
    assert job_title == new_title, "Did not update job title correctly, expected '#{new_title}' but found '#{job_title}'"

    puts "#{File.basename(__FILE__)}: '#{self.method_name}' successful!"
  end

  ##
  ## CONFIGURATIONS TESTS
  ## Test AdminConfiguration functionality and other site admin features
  ##

  # test the various levels of firecloud access integration (on, read-only, local-off, and off)
  test 'configurations: firecloud access' do
    puts "#{File.basename(__FILE__)}: '#{self.method_name}'"

    @driver.get @base_url
    login($test_email, $test_email_password)

    path = @base_url + '/admin'
    @driver.get path

    # show the 'panic' modal and disable downloads
    panic_modal_link = @driver.find_element(:id, 'show-panic-modal')
    panic_modal_link.click
    wait_for_modal_open('panic-modal')
    disable_button = @driver.find_element(:id, 'disable-firecloud-access')
    disable_button.click
    close_modal('message_modal')

    # assert access is revoked
    firecloud_url = "https://app.terra.bio/#workspaces/single-cell-portal-#{$env}/test-study-#{$random_seed}"
    @driver.get firecloud_url
    accept_firecloud_tos
    assert !element_present?(:class, 'fa-pen'), 'did not revoke access - study workspace still loads'

    # test that study admin access is disabled
    # go to homepage first to set referrer
    @driver.get @base_url
    studies_path = @base_url + '/studies'
    @driver.get studies_path
    assert element_present?(:id, 'message_modal'), 'did not show alert'
    assert @driver.current_url == @base_url, 'did not redirect to home page'

    # set access to readonly
    @driver.get path
    panic_modal_link = @driver.find_element(:id, 'show-panic-modal')
    panic_modal_link.click
    wait_for_modal_open('panic-modal')
    compute_button = @driver.find_element(:id, 'disable-compute-access')
    compute_button.click
    close_modal('message_modal')

    # assert access is revoked
    @driver.get firecloud_url
    assert !element_present?(:class, 'fa-trash'), 'did not revoke compute access - study workspace can still be deleted'

    # test that study admin access is disabled
    # go to homepage first to set referrer
    @driver.get @base_url
    studies_path = @base_url + '/studies'
    @driver.get studies_path
    assert element_present?(:id, 'message_modal'), 'did not show alert'
    assert @driver.current_url == @base_url, 'did not redirect to home page'

    # now restore access
    @driver.get path
    panic_modal_link = @driver.find_element(:id, 'show-panic-modal')
    panic_modal_link.click
    wait_for_modal_open('panic-modal')
    disable_button = @driver.find_element(:id, 'enable-firecloud-access')
    disable_button.click
    close_modal('message_modal')

    # assert access is restored, wait a few seconds for changes to propogate
    sleep(3)
    @driver.get firecloud_url
    assert element_present?(:class, 'fa-pen'), 'did not restore access - study workspace does not load'

    # assert study access is restored
    @driver.get studies_path
    assert element_present?(:id, 'studies'), 'did not find studies table'
    assert @driver.current_url == studies_path, 'did not load studies path correctly'

    # finally, check local-only option to block downloads and study access in the portal only
    @driver.get path
    panic_modal_link = @driver.find_element(:id, 'show-panic-modal')
    panic_modal_link.click
    wait_for_modal_open('panic-modal')
    local_access_button = @driver.find_element(:id, 'disable-local-access')
    local_access_button.click
    close_modal('message_modal')

    # assert firecloud projects are still accessible, but studies and downloads are not
    @driver.get firecloud_url
    assert element_present?(:class, 'fa-pen'), 'did maintain restore access - study workspace does not load'
    test_study_path = @base_url + "/study/test-study-#{$random_seed}"
    @driver.get(test_study_path)
    wait_for_render(:id, 'study-download-nav')
    open_ui_tab('study-download')
    disabled_downloads = @driver.find_elements(:class, 'disabled-download')
    assert disabled_downloads.size > 0, 'did not disable downloads, found 0 disabled-download links'
    @driver.get studies_path
    assert element_present?(:id, 'message_modal'), 'did not show alert'
    assert @driver.current_url == @base_url, 'did not redirect to home page'

    # cleanup by restoring access
    @driver.get path
    panic_modal_link = @driver.find_element(:id, 'show-panic-modal')
    panic_modal_link.click
    wait_for_modal_open('panic-modal')
    disable_button = @driver.find_element(:id, 'enable-firecloud-access')
    disable_button.click
    close_modal('message_modal')

    puts "#{File.basename(__FILE__)}: '#{self.method_name}' successful!"
  end

  # validate that the download quota will prevent user downloads once reached
  test 'configurations: quota: enforcement' do
    puts "#{File.basename(__FILE__)}: '#{self.method_name}'"

    @driver.get @base_url
    login($test_email, $test_email_password)

    path = @base_url + '/admin'
    @driver.get path

    # find quota object or create if needed
    if element_present?(:class, 'daily-user-download-quota-edit')
      quota_edit = @driver.find_element(:class, 'daily-user-download-quota-edit')
      quota_edit.click
      multiplier = @driver.find_element(:id, 'admin_configuration_multiplier')
      multiplier.send_keys('byte')
      save = @driver.find_element(:id, 'save-configuration')
      save.click
      wait_until_page_loads(path)
      close_modal('message_modal')
    else
      create = @driver.find_element(id: 'create-new-configuration')
      create.click
      value = @driver.find_element(:id, 'admin_configuration_value')
      value.send_keys(2)
      multiplier = @driver.find_element(:id, 'admin_configuration_multiplier')
      multiplier.send_keys('byte')
      save = @driver.find_element(:id, 'save-configuration')
      save.click
      wait_until_page_loads(path)
      close_modal('message_modal')
    end

    # now test downloads
    study_path = @base_url + "/study/test-study-#{$random_seed}"
    @driver.get(study_path)
    study_accession = extract_accession_from_url(@driver.current_url)
    loaded_study_path = @base_url + "/study/#{study_accession}/test-study-#{$random_seed}"
    wait_until_page_loads(loaded_study_path)

    open_ui_tab('study-download')

    files = @driver.find_elements(:class, 'disabled-download')
    assert files.size >= 1, 'downloads not properly disabled (did not find any disabled-download links)'

    # try bypassing download with a direct call to file we uploaded earlier

    direct_link = @base_url + "/data/public/#{study_accession}/test-study-#{$random_seed}?filename=expression_matrix_example.txt"
    @driver.get direct_link
    alert_content = @driver.find_element(:id, 'alert-content')
    assert alert_content.text == 'You have exceeded your current daily download quota. You must wait until tomorrow to download this file.', 'download was not successfully blocked'

    # reset quota back to default, we don't need to test downloads again because that gets done in front-end: download study data file
    @driver.get path
    quota_edit = @driver.find_element(:class, 'daily-user-download-quota-edit')
    quota_edit.click
    multiplier = @driver.find_element(:id, 'admin_configuration_multiplier')
    multiplier.send_keys('terabyte')
    save = @driver.find_element(:id, 'save-configuration')
    save.click
    wait_until_page_loads(path)
    close_modal('message_modal')

    puts "#{File.basename(__FILE__)}: '#{self.method_name}' successful!"
  end

  # test unlocking jobs feature - this mainly just tests that the request goes through. it is difficult to test the
  # entire method as it require the portal to crash while in the middle of a parse, which cannot be reliably automated.
  test 'configurations: restart locked jobs' do
    puts "#{File.basename(__FILE__)}: '#{self.method_name}'"
    @driver.get @base_url
    login($test_email, $test_email_password)
    @driver.get @base_url + '/admin'

    actions_dropdown = @driver.find_element(:id, 'admin_action')
    actions_dropdown.send_keys 'Unlock Orphaned Jobs'
    execute_button = @driver.find_element(:id, 'perform-admin-task')
    execute_button.click
    wait_for_modal_open('message_modal')
    assert element_visible?(:id, 'message_modal'), 'confirmation message did not appear'
    message = @driver.find_element(:id, 'notice-content').text
    assert message.include?('jobs'), "'confirmation message did not pertain to locked jobs ('jobs' not found)"

    puts "#{File.basename(__FILE__)}: '#{self.method_name}' successful!"
  end

  # reset user download quotas to 0 bytes
  test 'configurations: download-quota: reset' do
    puts "#{File.basename(__FILE__)}: '#{self.method_name}'"
    @driver.get @base_url
    login($test_email, $test_email_password)

    @driver.get @base_url + '/admin'

    actions_dropdown = @driver.find_element(:id, 'admin_action')
    actions_dropdown.send_keys 'Reset User Download Quotas'
    execute_button = @driver.find_element(:id, 'perform-admin-task')
    execute_button.click
    wait_for_modal_open('message_modal')
    assert element_visible?(:id, 'message_modal'), 'confirmation message did not appear'
    message = @driver.find_element(:id, 'notice-content').text
    expected_conf = 'All user download quotas successfully reset to 0.'
    assert message == expected_conf, "correct confirmation did not appear, expected #{expected_conf} but found #{message}"

    puts "#{File.basename(__FILE__)}: '#{self.method_name}' successful!"
  end

  # test force-refreshing the FireCloud API access tokens and storage driver connections
  test 'configurations: refresh api connections' do
    puts "#{File.basename(__FILE__)}: '#{self.method_name}'"

    @driver.get @base_url
    login($test_email, $test_email_password)
    path = @base_url + '/admin'
    @driver.get path

    actions_dropdown = @driver.find_element(:id, 'admin_action')
    actions_dropdown.send_keys 'Refresh API Clients'
    execute_button = @driver.find_element(:id, 'perform-admin-task')
    execute_button.click
    wait_for_modal_open('message_modal')
    assert element_visible?(:id, 'message_modal'), 'confirmation message did not appear'
    message = @driver.find_element(:id, 'notice-content').text
    expected_conf = 'API Client successfully refreshed.'
    assert message.start_with?(expected_conf), "correct confirmation did not appear, expected #{expected_conf} but found #{message}"

    puts "#{File.basename(__FILE__)}: '#{self.method_name}' successful!"
  end

  # update a user's roles (admin or reporter)
  test 'configurations: update user roles' do
    puts "#{File.basename(__FILE__)}: '#{self.method_name}'"

    @driver.get @base_url
    login($test_email, $test_email_password)
    path = @base_url + '/admin'
    @driver.get path

    open_ui_tab('users')
    share_email_id = $share_email.gsub(/[@.]/, '-')
    search_box = @driver.find_element(:xpath, "//div[@id='users']//input[@type='search']")
    search_box.send_keys($share_email)
    share_user_edit = @driver.find_element(:id, share_email_id + '-edit')
    share_user_edit.click
    wait_for_render(:id, 'user_reporter')
    user_reporter = @driver.find_element(:id, 'user_reporter')
    user_reporter.send_keys('Yes')
    save_btn = @driver.find_element(:id, 'save-user')
    save_btn.click

    # assert that reporter access was granted
    close_modal('message_modal')
    open_ui_tab('users')
    search_box = @driver.find_element(:xpath, "//div[@id='users']//input[@type='search']")
    search_box.send_keys($share_email)
    assert element_present?(:id, share_email_id + '-reporter'), "did not grant reporter access to #{$share_email}"

    # now remove to reset for future tests
    share_user_edit = @driver.find_element(:id, share_email_id + '-edit')
    share_user_edit.click
    wait_for_render(:id, 'user_reporter')
    user_reporter = @driver.find_element(:id, 'user_reporter')
    user_reporter.send_keys('No')
    save_btn = @driver.find_element(:id, 'save-user')
    save_btn.click

    # assert that reporter access was removed
    close_modal('message_modal')
    open_ui_tab('users')
    search_box = @driver.find_element(:xpath, "//div[@id='users']//input[@type='search']")
    search_box.send_keys($share_email)
    share_roles = @driver.find_element(:id, share_email_id + '-roles')
    assert share_roles.text == '', "did not remove reporter access from #{$share_email}"

    puts "#{File.basename(__FILE__)}: '#{self.method_name}' successful!"
  end

  # test whether or not maintenance mode functions properly
  # technically this is not an AdminConfiguration, but a bash script that only a project admin can invoke
  test 'configurations: maintenance mode' do
    puts "#{File.basename(__FILE__)}: '#{self.method_name}'"
    # only execute this test when testing locally - when using a remote host it will fail as the shell script being executed
    # is on the wrong host
    omit_if !$portal_url.include?('localhost'), 'cannot enable maintenance mode on remote host' do
      # enable maintenance mode
      system("#{@base_path}/bin/enable_maintenance.sh on")
      @driver.get @base_url
      assert element_present?(:id, 'maintenance-notice'), 'could not load maintenance page'
      # disable maintenance mode
      system("#{@base_path}/bin/enable_maintenance.sh off")
      @driver.get @base_url
      assert element_present?(:id, 'main-banner'), 'could not load home page'
      puts "#{File.basename(__FILE__)}: '#{self.method_name}' successful!"
    end
  end

  # test sending an email to users
  test 'configurations: email all users' do
    puts "#{File.basename(__FILE__)}: '#{self.method_name}'"

    @driver.get @base_url
    login($test_email, $test_email_password)
    path = @base_url + '/admin'
    @driver.get path

    email_users_btn = @driver.find_element(:id, 'email-all-users')
    email_users_btn.click
    wait_until_page_loads(path + '/email_users/compose')

    subject = @driver.find_element(:id, 'email_subject')
    subject.send_keys('This is the subject')
    message = @driver.find_element(:class, 'ck-editor__editable')
    message_content = "This is an email to all users."
    message.send_keys(message_content)

    # send preview email
    preview_btn = @driver.find_element(:id, 'deliver-preview-email')
    preview_btn.click
    wait_for_modal_open('message_modal')
    notification = @driver.find_element(:id, 'notice-content')
    assert notification.text == 'Your email has successfully been delivered.', "Did not find correct notification, expeceted 'Your email has successfully been delivered.' but found '#{notification.text}'"
    close_modal('message_modal')
    sleep(2)

    # send regular email
    deliver_btn = @driver.find_element(:id, 'deliver-users-email')
    deliver_btn.click
    wait_for_modal_open('message_modal')
    new_notification = @driver.find_element(:id, 'notice-content')
    assert new_notification.text == 'Your email has successfully been delivered.', "Did not find correct notification, expeceted 'Your email has successfully been delivered.' but found '#{new_notification.text}'"

    puts "#{File.basename(__FILE__)}: '#{self.method_name}' successful!"
  end

  ##
  ## REPORTS TESTS
  ## View portal statistics through the reports page
  ##

  # test loading plots from reporting controller
  test 'reports: view' do
    puts "#{File.basename(__FILE__)}: '#{self.method_name}'"

    @driver.get @base_url
    login($test_email, $test_email_password)

    path = @base_url + '/reports'
    @driver.get(path)

    # check for reports
    report_plots = @driver.find_elements(:class, 'plotly-report')
    assert report_plots.size == 9 || report_plots.size == 11,
           "did not find correct number of plots, expected 9 or 11 but found #{report_plots.size}"
    report_plots.each do |plot|
      rendered = @driver.execute_script("return $('##{plot['id']}').data('rendered')")
      assert rendered, "#{plot['id']} rendered status was not true"
    end

    # test toggle column total button
    toggle_btn = @driver.find_element(:id, 'toggle-column-annots')

    # turn off
    toggle_btn.click
    @wait.until {wait_for_plotly_render('#plotly-study-email-domain-dist', 'rendered')}
    new_layout = @driver.execute_script("return document.getElementById('plotly-study-email-domain-dist').layout")
    assert new_layout['annotations'].nil?, "did not turn off annotations, expected nil but found #{new_layout['annotations']}"

    # turn on
    toggle_btn.click
    @wait.until {wait_for_plotly_render('#plotly-study-email-domain-dist', 'rendered')}
    layout = @driver.execute_script("return document.getElementById('plotly-study-email-domain-dist').layout")
    assert !layout['annotations'].nil?, "did not turn on annotations, expected annotations array but found #{layout['annotations']}"

    # if present, export pipeline stats
    if element_present?(:id, 'export-submission-report')
      export_btn = @driver.find_element(:id, 'export-submission-report')
      export_btn.click

      filename = "analysis_submissions_#{Date.today.strftime('%F')}.txt"
      download_path = File.join($download_dir, filename)

      i = 0
      while !File.exists?(download_path)
        omit_if i >= 30, 'Skipping test; waited 30 seconds but no submission report complete yet.'
        sleep 1
        i += 1
      end
      submission_report = File.open(download_path)
      headers = submission_report.readline.split("\t").map(&:strip)
      expected_headers = %w(email analysis status submission_date completion_date firecloud_workspace study_info_url)
      assert headers == expected_headers,
             "Did not find correctly formatted report, expected headers of '#{expected_headers.join(', ')}' but found '#{headers.join(', ')}'"

      # clean up
      submission_report.close
      File.delete(download_path)
    end

    puts "#{File.basename(__FILE__)}: '#{self.method_name}' successful!"
  end

  # send a request to site admins for a new report plot
  test 'reports: request new' do
    puts "#{File.basename(__FILE__)}: '#{self.method_name}'"

    @driver.get @base_url
    login($test_email, $test_email_password)

    path = @base_url + '/reports'
    @driver.get(path)

    request_modal = @driver.find_element(:id, 'report-request')
    request_modal.click

    message = @driver.find_element(:class, 'ck-editor__editable')
    message_content = "This is a report request."
    message.send_keys(message_content)
    send_request = @driver.find_element(:id, 'send-report-request')
    send_request.click
    wait_for_modal_open('message_modal')
    assert element_visible?(:id, 'message_modal'), 'confirmation modal did not show.'
    notice_content = @driver.find_element(:id, 'notice-content')
    confirmation_message = 'Your request has been submitted.'
    assert notice_content.text == confirmation_message, "did not find confirmation message, expected #{confirmation_message} but found #{notice_content.text}"

    puts "#{File.basename(__FILE__)}: '#{self.method_name}' successful!"
  end

  ###
  #
  # FRONT-END TESTS
  #
  ###

  ##
  ## FRONT-END BASIC TESTS
  ## Covers basic front-end functionality (mostly the study overview page)
  ##

  # get the homepage
  test 'front-end: view: home page' do
    puts "#{File.basename(__FILE__)}: '#{self.method_name}'"

    @driver.get(@base_url)
    assert element_present?(:id, 'main-banner'), 'could not find index page title text'
    assert @driver.find_elements(:class, 'study-panel').size >= 1, 'did not find any studies'
    puts "#{File.basename(__FILE__)}: '#{self.method_name}' successful!"
  end

  # search for studies
  test 'front-end: search' do
    puts "#{File.basename(__FILE__)}: '#{self.method_name}'"

    @driver.get(@base_url)
    search_box = @driver.find_element(:id, 'search_terms')
    search_box.send_keys("#{$random_seed}")
    submit = @driver.find_element(:id, 'submit-search')
    submit.click
    studies = @driver.find_elements(:class, 'study-panel').size
    assert studies >= 2, 'incorrect number of studies found. expected >= 2 but found ' + studies.to_s
    # first load study and get accession value
    path = @base_url + "/study/test-study-#{$random_seed}"
    @driver.get(path)
    study_accession = extract_accession_from_url(@driver.current_url)
    loaded_path = @base_url + "/study/#{study_accession}/test-study-#{$random_seed}"
    wait_until_page_loads(loaded_path)

    # now search by accession
    @driver.get(@base_url)
    search_box = @driver.find_element(:id, 'search_terms')
    search_box.send_keys("#{study_accession}")
    submit = @driver.find_element(:id, 'submit-search')
    submit.click
    studies = @driver.find_elements(:class, 'study-panel').size
    assert studies == 1, "Did not load single study by accession value: #{study_accession}, expected 1 but found #{studies}"
    puts "#{File.basename(__FILE__)}: '#{self.method_name}' successful!"
  end

  # view study overview pages
  test 'front-end: view: study' do
    puts "#{File.basename(__FILE__)}: '#{self.method_name}'"

    path = @base_url + "/study/test-study-#{$random_seed}"
    @driver.get(path)
    study_accession = extract_accession_from_url(@driver.current_url)
    loaded_path = @base_url + "/study/#{study_accession}/test-study-#{$random_seed}"
    wait_until_page_loads(loaded_path)
    open_ui_tab('study-visualize')

    assert element_present?(:class, 'study-lead'), 'could not find study title'
    assert element_present?(:id, 'cluster-plot'), 'could not find study cluster plot'

    # wait until cluster finishes rendering
    @wait.until {wait_for_plotly_render('#cluster-plot', 'rendered')}
    rendered = @driver.execute_script("return $('#cluster-plot').data('rendered')")
    assert rendered, "cluster plot did not finish rendering, expected true but found #{rendered}"

    # check for coordinate labels
    # SCP-2072: figure out how to get these back into first create-study: test so we can assert this
    # labels = @driver.execute_script("return layout.scene.annotations;")
    # assert_not_nil labels, 'Did not return coordinate labels'
    # assert labels.size == 8, "Did not find coorect number of coordinate labels, expected 8 but found #{labels.size}"

    # load subclusters
    view_options_panel = @driver.find_element(:id, 'view-option-link')
    view_options_panel.click
    wait_for_render(:id, 'view-options')
    clusters = @driver.find_element(:id, 'cluster').find_elements(:tag_name, 'option')
    assert clusters.size == 2, "incorrect number of clusters found, expected 2 but found #{clusters.size}"
    annotations = @driver.find_element(:id, 'annotation').find_elements(:tag_name, 'option')
    assert annotations.size == 5, "incorrect number of annotations found, expected 5 but found #{annotations.size}"
    annotations.select {|opt| opt.text == 'Sub-Cluster'}.first.click

    # wait for render again
    @wait.until {wait_for_plotly_render('#cluster-plot', 'rendered')}
    sub_rendered = @driver.execute_script("return $('#cluster-plot').data('rendered')")
    assert sub_rendered, "cluster plot did not finish rendering on change, expected true but found #{sub_rendered}"
    legend = @driver.find_elements(:class, 'traces').size
    assert legend == 6, "incorrect number of traces found in Sub-Cluster, expected 6 - found #{legend}"

    # testing loading all annotation types
    annotations_values = annotations.map{|x| x['value']}
    annotations_values.each do |annotation|
      @driver.find_element(:id, 'annotation').send_key annotation
      @wait.until {wait_for_plotly_render('#cluster-plot', 'rendered')}
      cluster_rendered = @driver.execute_script("return $('#cluster-plot').data('rendered')")
      assert cluster_rendered, "cluster plot did not finish rendering on change, expected true but found #{cluster_rendered}"
    end

    # Test rendering of clusters with percent signs in name
    clusters.select {|opt| opt.text == 'Test Cluster 2'}.first.click
    sleep(1) # let 'rendered' for #cluster-plot set to false
    @wait.until {wait_for_plotly_render('#cluster-plot', 'rendered')}
    annotations = @driver.find_element(:id, 'annotation').find_elements(:tag_name, 'option')
    annotations.select {|opt| opt.text == 'Has % sign'}.first.click
    @wait.until {wait_for_plotly_render('#cluster-plot', 'rendered')}
    sub_rendered = @driver.execute_script("return $('#cluster-plot').data('rendered')")
    assert sub_rendered, "plot for cluster with percent sign in name did not finish rendering on change, expected true but found #{sub_rendered}"

    # now test private study
    login($test_email, $test_email_password)
    private_study_path = @base_url + "/study/private-study-#{$random_seed}"
    @driver.get private_study_path
    study_accession = extract_accession_from_url(@driver.current_url)
    loaded_private_study_path = @base_url + "/study/#{study_accession}/private-study-#{$random_seed}"
    wait_until_page_loads(loaded_private_study_path)
    open_ui_tab('study-visualize')

    @wait.until {wait_for_plotly_render('#cluster-plot', 'rendered')}
    private_rendered = @driver.execute_script("return $('#cluster-plot').data('rendered')")
    assert private_rendered, "private cluster plot did not finish rendering, expected true but found #{private_rendered}"

    puts "#{File.basename(__FILE__)}: '#{self.method_name}' successful!"
  end

  # download a study file
  test 'front-end: download: study file' do
    puts "#{File.basename(__FILE__)}: '#{self.method_name}'"
    @driver.get @base_url
    login($test_email, $test_email_password)

    path = @base_url + "/study/test-study-#{$random_seed}"

    @driver.get(path)
    study_accession = extract_accession_from_url(@driver.current_url)
    loaded_path = @base_url + "/study/#{study_accession}/test-study-#{$random_seed}"
    wait_until_page_loads(loaded_path)
    open_ui_tab('study-download')

    files = @driver.find_elements(:class, 'dl-link')
    file_link = files.sample
    filename = file_link['data-filename']
    basename = filename.split('.').first
    @wait.until { file_link.displayed? }
    # perform 'Save as' action
    download_file(file_link, basename)

    # now download a file from a private study
    private_path = @base_url + "/study/private-study-#{$random_seed}"
    @driver.get(private_path)
    study_accession = extract_accession_from_url(@driver.current_url)
    loaded_private_path = @base_url + "/study/#{study_accession}/private-study-#{$random_seed}"
    wait_until_page_loads(loaded_private_path)
    open_ui_tab('study-download')

    private_files = @driver.find_elements(:class, 'dl-link')
    private_file_link = private_files.first
    private_filename = private_file_link['download']
    private_basename = private_filename.split('.').first
    @wait.until { private_file_link.displayed? }
    download_file(private_file_link, private_basename)

    # logout
    logout_from_portal

    # now login as share user and test downloads
    login_as_other($share_email, $share_email_password)

    @driver.get(loaded_path)
    wait_until_page_loads(loaded_path)
    open_ui_tab('study-download')

    files = @driver.find_elements(:class, 'dl-link')
    share_file_link = files.first
    share_filename = share_file_link['data-filename']
    share_basename = share_filename.split('.').first
    @wait.until { share_file_link.displayed? }
    download_file(share_file_link, share_basename)

    puts "#{File.basename(__FILE__)}: '#{self.method_name}' successful!"
  end

  # test view/edit restrictions on private studies
  test 'front-end: download: privacy restriction' do
    puts "#{File.basename(__FILE__)}: '#{self.method_name}'"

    @driver.get @base_url
    login($test_email, $test_email_password)

    # get the accession for the private study
    private_path = @base_url + "/study/private-study-#{$random_seed}"
    @driver.get(private_path)
    study_accession = extract_accession_from_url(@driver.current_url)
    loaded_private_path = @base_url + "/study/#{study_accession}/private-study-#{$random_seed}"
    wait_until_page_loads(loaded_private_path)

    logout_from_portal
    @driver.get @base_url
    login_as_other($share_email, $share_email_password)
    # negative test, should not be able to download private files from study without access
    non_share_public_link = @base_url + "/data/public/#{study_accession}/private-study-#{$random_seed}?filename=README.txt"
    non_share_private_link = @base_url + "/data/private/#{study_accession}/private-study-#{$random_seed}?filename=README.txt"

    # try public route
    @driver.get non_share_public_link
    public_alert_text = @driver.find_element(:id, 'alert-content').text
    assert public_alert_text == 'You do not have permission to perform that action.',
           "did not properly redirect, expected 'You do not have permission to perform that action.' but got #{public_alert_text}"

    # try private route
    @driver.get non_share_private_link
    wait_for_modal_open('message_modal')
    private_alert_text = @driver.find_element(:id, 'alert-content').text
    assert private_alert_text == 'You do not have permission to perform that action.',
           "did not properly redirect, expected 'You do not have permission to perform that action.' but got #{private_alert_text}"

    puts "#{File.basename(__FILE__)}: '#{self.method_name}' successful!"
  end

  test 'front-end: download: bulk data' do
    puts "#{File.basename(__FILE__)}: '#{self.method_name}'"

    @driver.get @base_url
    login($share_email, $share_email_password)

    path = @base_url + "/study/sync-test-#{$random_seed}"
    @driver.get(path)
    study_accession = extract_accession_from_url(@driver.current_url)
    loaded_path = @base_url + "/study/#{study_accession}/sync-test-#{$random_seed}"
    wait_until_page_loads(loaded_path)
    open_ui_tab('study-download')

    # open download help modal
    download_modal = @driver.find_element(id: 'download-help')
    download_modal.click
    wait_for_modal_open('download-help-modal')

    # get command for all data download
    all_data_link = @driver.find_element(:id, 'get-download-command_all')
    all_data_link.click
    wait_for_render(:class, 'curl-download-command')
    command_value = @driver.find_element(:class, 'curl-download-command')['value']

    # run command and verify that download works
    system("cd #{$download_dir}; mkdir #{$random_seed}; cd #{$random_seed}; #{command_value}")
    bulk_path = File.join($download_dir, $random_seed)
    files_found = Dir.entries(bulk_path).keep_if {|entry| !entry.start_with?('.')}.size
    assert files_found > 0, 'did not download any files'

    # clean up
    FileUtils.rm_rf(bulk_path)

    puts "#{File.basename(__FILE__)}: '#{self.method_name}' successful!"
  end

  # test that axes are rendering custom domains and labels properly
  test 'front-end: validation: axis domains and labels' do
    puts "#{File.basename(__FILE__)}: '#{self.method_name}'"

    path = @base_url + "/study/test-study-#{$random_seed}"
    @driver.get(path)
    study_accession = extract_accession_from_url(@driver.current_url)
    loaded_path = @base_url + "/study/#{study_accession}/test-study-#{$random_seed}"
    wait_until_page_loads(loaded_path)
    open_ui_tab('study-visualize')

    assert element_present?(:class, 'study-lead'), 'could not find study title'
    assert element_present?(:id, 'cluster-plot'), 'could not find study cluster plot'

    # wait until cluster finishes rendering
    @wait.until {wait_for_plotly_render('#cluster-plot', 'rendered')}
    rendered = @driver.execute_script("return $('#cluster-plot').data('rendered')")
    assert rendered, "cluster plot did not finish rendering, expected true but found #{rendered}"

    # get layout object from browser and verify labels & ranges
    layout = @driver.execute_script('return layout;')
    assert layout['scene']['xaxis']['range'] == [-100, 100], "X range was not correctly set, expected [-100, 100] but found #{layout['scene']['xaxis']['range']}"
    assert layout['scene']['yaxis']['range'] == [-75, 75], "Y range was not correctly set, expected [-75, 75] but found #{layout['scene']['xaxis']['range']}"
    assert layout['scene']['zaxis']['range'] == [-125, 125], "Z range was not correctly set, expected [-125, 125] but found #{layout['scene']['xaxis']['range']}"
    assert layout['scene']['xaxis']['title'] == 'X Axis', "X title was not set correctly, expected 'X Axis' but found #{layout['scene']['xaxis']['title']}"
    assert layout['scene']['yaxis']['title'] == 'Y Axis', "Y title was not set correctly, expected 'Y Axis' but found #{layout['scene']['yaxis']['title']}"
    assert layout['scene']['zaxis']['title'] == 'Z Axis', "Z title was not set correctly, expected 'Z Axis' but found #{layout['scene']['zaxis']['title']}"
    puts "#{File.basename(__FILE__)}: '#{self.method_name}' successful!"
  end

  # test that toggle traces button works
  test 'front-end: validation: toggle traces button' do
    puts "#{File.basename(__FILE__)}: '#{self.method_name}'"

    path = @base_url + "/study/test-study-#{$random_seed}"
    @driver.get(path)
    study_accession = extract_accession_from_url(@driver.current_url)
    loaded_path = @base_url + "/study/#{study_accession}/test-study-#{$random_seed}"
    wait_until_page_loads(loaded_path)
    open_ui_tab('study-visualize')

    assert element_present?(:class, 'study-lead'), 'could not find study title'
    assert element_present?(:id, 'cluster-plot'), 'could not find study cluster plot'

    # wait until cluster finishes rendering
    @wait.until {wait_for_plotly_render('#cluster-plot', 'rendered')}
    rendered = @driver.execute_script("return $('#cluster-plot').data('rendered')")
    assert rendered, "cluster plot did not finish rendering, expected true but found #{rendered}"

    view_options_panel = @driver.find_element(:id, 'view-option-link')
    view_options_panel.click
    wait_for_render(:id, 'view-options')

    # open distribution control panel as well to get toggle annotations button
    view_options_panel = @driver.find_element(:id, 'distribution-panel-link')
    view_options_panel.click
    wait_for_render(:id, 'toggle-traces')

    # toggle traces off
    toggle = @driver.find_element(:id, 'toggle-traces')
    toggle.click

    # check visiblity
    visible = @driver.execute_script('return data[0].visible')
    assert visible == 'legendonly', "did not toggle trace visibility, expected 'legendonly' but found #{visible}"

    # toggle traces on
    toggle.click

    # check visiblity
    visible = @driver.execute_script('return data[0].visible')
    assert visible == true, "did not toggle trace visibility, expected 'true' but found #{visible}"
    puts "#{File.basename(__FILE__)}: '#{self.method_name}' successful!"
  end

  ##
  ## FRONT-END: SEARCHING EXPRESSION DATA
  ## Tests front-end functionality when searching for genes and viewing expression data
  ##

  # search for a single gene and view plots
  test 'front-end: view: search-genes: single' do
    puts "#{File.basename(__FILE__)}: '#{self.method_name}'"

    path = @base_url + "/study/test-study-#{$random_seed}"
    @driver.get(path)
    study_accession = extract_accession_from_url(@driver.current_url)
    loaded_path = @base_url + "/study/#{study_accession}/test-study-#{$random_seed}"
    wait_until_page_loads(loaded_path)
    open_ui_tab('study-visualize')

    # perform negative search first to test redirect
    bad_gene = 'foo'
    search_box = @driver.find_element(:id, 'search_genes')
    search_box.send_keys(bad_gene)
    search_genes = @driver.find_element(:id, 'perform-gene-search')
    search_genes.click
    wait_for_modal_open('message_modal')
    alert_text = @driver.find_element(:id, 'alert-content')
    assert alert_text.text == 'No matches found for: foo.', 'did not redirect and display alert correctly'
    close_modal('message_modal')

    # load random gene to search
    gene = @genes.sample
    search_box = @driver.find_element(:id, 'search_genes')
    search_box.send_keys(gene)
    search_genes = @driver.find_element(:id, 'perform-gene-search')
    search_genes.click
    assert element_present?(:id, 'box-controls'), 'could not find expression violin plot'
    assert element_present?(:id, 'scatter-plots'), 'could not find expression scatter plots'

    # confirm queried gene is the one returned
    queried_gene = @driver.find_element(:class, 'queried-gene')
    assert queried_gene.text == gene, "did not load the correct gene, expected #{gene} but found #{queried_gene.text}"

    # testing loading all annotation types
    @wait.until {wait_for_plotly_render('#expression-plots', 'box-rendered')}
    view_options_panel = @driver.find_element(:id, 'view-option-link')
    view_options_panel.click
    wait_for_render(:id, 'view-options')
    annotations = @driver.find_element(:id, 'annotation').find_elements(:tag_name, 'option')
    annotations_values = annotations.map{|x| x['value']}
    annotations_values.each do |annotation|
      @driver.find_element(:id, 'annotation').send_key annotation
      type = annotation.split('--')[1]
      $verbose ? puts( "loading annotation: #{annotation}") : nil
      if type == 'group'
        # if looking at box, switch back to violin
        @wait.until {wait_for_plotly_render('#expression-plots', 'box-rendered')}
        plot_dropdown = @driver.find_element(:id, 'plot_type')
        plot_ops = plot_dropdown.find_elements(:tag_name, 'option')

        is_box_plot = plot_ops.select {|opt| opt.selected?}.sample.text == 'Box Plot'
        if is_box_plot
          new_plot = plot_ops.select {|opt| !opt.selected?}.sample.text
          plot_dropdown.send_keys(new_plot)
        end
        # wait until violin plot renders, at this point all 3 should be done

        @wait.until {wait_for_plotly_render('#expression-plots', 'box-rendered')}
        violin_rendered = @driver.execute_script("return $('#expression-plots').data('box-rendered')")
        assert violin_rendered, "violin plot did not finish rendering, expected true but found #{violin_rendered}"
        scatter_rendered = @driver.execute_script("return $('#expression-plots').data('scatter-rendered')")
        assert scatter_rendered, "scatter plot did not finish rendering, expected true but found #{scatter_rendered}"
        reference_rendered = @driver.execute_script("return $('#expression-plots').data('reference-rendered')")
        assert reference_rendered, "reference plot did not finish rendering, expected true but found #{reference_rendered}"

        # change to box plot
        plot_dropdown = @driver.find_element(:id, 'plot_type')
        plot_ops = plot_dropdown.find_elements(:tag_name, 'option')
        new_plot = plot_ops.select {|opt| !opt.selected?}.sample.text
        plot_dropdown.send_keys(new_plot)

        # wait until box plot renders, at this point all 3 should be done
        @wait.until {wait_for_plotly_render('#expression-plots', 'box-rendered')}
        box_rendered = @driver.execute_script("return $('#expression-plots').data('box-rendered')")
        assert box_rendered, "box plot did not finish rendering, expected true but found #{box_rendered}"
        scatter_rendered = @driver.execute_script("return $('#expression-plots').data('scatter-rendered')")
        assert scatter_rendered, "scatter plot did not finish rendering, expected true but found #{scatter_rendered}"
        reference_rendered = @driver.execute_script("return $('#expression-plots').data('reference-rendered')")
        assert reference_rendered, "reference plot did not finish rendering, expected true but found #{reference_rendered}"

      else
        @wait.until {wait_for_plotly_render('#expression-plots', 'box-rendered')}
        box_rendered = @driver.execute_script("return $('#expression-plots').data('box-rendered')")
        assert box_rendered, "box plot did not finish rendering, expected true but found #{box_rendered}"
        scatter_rendered = @driver.execute_script("return $('#expression-plots').data('scatter-rendered')")
        assert scatter_rendered, "scatter plot did not finish rendering, expected true but found #{scatter_rendered}"
        reference_rendered = @driver.execute_script("return $('#expression-plots').data('reference-rendered')")
        assert reference_rendered, "reference plot did not finish rendering, expected true but found #{reference_rendered}"
      end

    end
    # now test private study
    login($test_email, $test_email_password)
    private_study_path = @base_url + "/study/private-study-#{$random_seed}"
    @driver.get private_study_path
    study_accession = extract_accession_from_url(@driver.current_url)
    loaded_private_study_path = @base_url + "/study/#{study_accession}/private-study-#{$random_seed}"
    wait_until_page_loads(loaded_private_study_path)
    open_ui_tab('study-visualize')

    new_gene = @genes.sample
    search_box = @driver.find_element(:id, 'search_genes')
    search_box.send_keys(new_gene)
    search_genes = @driver.find_element(:id, 'perform-gene-search')
    search_genes.click
    assert element_present?(:id, 'box-controls'), 'could not find expression boxplot'
    assert element_present?(:id, 'scatter-plots'), 'could not find expression scatter plots'

    # confirm queried gene is the one returned
    new_queried_gene = @driver.find_element(:class, 'queried-gene')
    assert new_queried_gene.text == new_gene, "did not load the correct gene, expected #{new_gene} but found #{new_queried_gene.text}"

    # wait until violin plot renders, at this point all 3 should be done
    @wait.until {wait_for_plotly_render('#expression-plots', 'box-rendered')}
    private_violin_rendered = @driver.execute_script("return $('#expression-plots').data('box-rendered')")
    assert private_violin_rendered, "private violin plot did not finish rendering, expected true but found #{private_violin_rendered}"
    private_scatter_rendered = @driver.execute_script("return $('#expression-plots').data('scatter-rendered')")
    assert private_scatter_rendered, "private scatter plot did not finish rendering, expected true but found #{private_scatter_rendered}"
    private_reference_rendered = @driver.execute_script("return $('#expression-plots').data('reference-rendered')")
    assert private_reference_rendered, "private reference plot did not finish rendering, expected true but found #{private_reference_rendered}"

    # Open view options panel
    view_options_panel = @driver.find_element(:id, 'view-option-link')
    view_options_panel.click
    wait_for_render(:id, 'view-options')

    # change to box plot
    private_plot_dropdown = @driver.find_element(:id, 'plot_type')
    private_plot_ops = private_plot_dropdown.find_elements(:tag_name, 'option')
    private_new_plot = private_plot_ops.select {|opt| !opt.selected?}.sample.text
    private_plot_dropdown.send_keys(private_new_plot)

    # wait until box plot renders, at this point all 3 should be done
    @wait.until {wait_for_plotly_render('#expression-plots', 'box-rendered')}
    private_box_rendered = @driver.execute_script("return $('#expression-plots').data('box-rendered')")
    assert private_box_rendered, "private box plot did not finish rendering, expected true but found #{private_box_rendered}"
    scatter_rendered = @driver.execute_script("return $('#expression-plots').data('scatter-rendered')")
    assert scatter_rendered, "private scatter plot did not finish rendering, expected true but found #{scatter_rendered}"
    reference_rendered = @driver.execute_script("return $('#expression-plots').data('reference-rendered')")
    assert reference_rendered, "private reference plot did not finish rendering, expected true but found #{reference_rendered}"

    puts "#{File.basename(__FILE__)}: '#{self.method_name}' successful!"
  end

  # search for multiple genes, but collapse using a consensus metric and view plots
  test 'front-end: view: search-genes: multiple consensus' do
    puts "#{File.basename(__FILE__)}: '#{self.method_name}'"

    path = @base_url + "/study/test-study-#{$random_seed}"
    @driver.get(path)
    study_accession = extract_accession_from_url(@driver.current_url)
    loaded_path = @base_url + "/study/#{study_accession}/test-study-#{$random_seed}"
    wait_until_page_loads(loaded_path)
    open_ui_tab('study-visualize')

    # load random genes to search, take between 2-5, adding in bad gene to test error handling
    genes = @genes.shuffle.take(rand(2..5))
    search_box = @driver.find_element(:id, 'search_genes')
    search_box.send_keys(genes.join(' ') + ' foo')

    search_menu = @driver.find_element(:id, 'search-omnibar-menu-icon')
    search_menu.click
    wait_for_render(:id, 'search_consensus')

    consensus = @driver.find_element(:id, 'search_consensus')

    # select a random consensus measurement
    opts = consensus.find_elements(:tag_name, 'option').delete_if {|o| o.text == 'None'}
    selected_consensus = opts.sample
    selected_consensus_value = selected_consensus['value']
    selected_consensus.click

    assert element_present?(:id, 'box-controls'), 'could not find expression boxplot'
    assert element_present?(:id, 'scatter-plots'), 'could not find expression scatter plots'
    assert element_present?(:id, 'missing-genes'), 'did not find missing genes list'

    # confirm queried genes and selected consensus are correct
    queried_genes = @driver.find_elements(:class, 'queried-gene').map(&:text)
    assert genes.sort == queried_genes.sort, "found incorrect genes, expected #{genes.sort} but found #{queried_genes.sort}"
    queried_consensus = @driver.find_element(:id, 'selected-consensus')
    assert selected_consensus_value == queried_consensus.text, "did not load correct consensus metric, expected #{selected_consensus_value} but found #{queried_consensus.text}"

    # testing loading all annotation types
    @wait.until {wait_for_plotly_render('#expression-plots', 'box-rendered')}
    view_options_panel = @driver.find_element(:id, 'view-option-link')
    view_options_panel.click
    wait_for_render(:id, 'view-options')

    # open distribution control panel as well
    view_options_panel = @driver.find_element(:id, 'distribution-panel-link')
    view_options_panel.click
    wait_for_render(:id, 'distribution-plot-controls')

    annotations = @driver.find_element(:id, 'annotation').find_elements(:tag_name, 'option')
    annotations_values = annotations.map{|x| x['value']}
    annotations_values.each do |annotation|
      @driver.find_element(:id, 'annotation').send_key annotation
      type = annotation.split('--')[1]
      $verbose ? puts( "loading annotation: #{annotation}") : nil
      if type == 'group'
        # if looking at box, switch back to violin
        @wait.until {wait_for_plotly_render('#expression-plots', 'box-rendered')}
        plot_dropdown = @driver.find_element(:id, 'plot_type')
        plot_ops = plot_dropdown.find_elements(:tag_name, 'option')

        is_box_plot = plot_ops.select {|opt| opt.selected?}.sample.text == 'Box Plot'
        if is_box_plot
          new_plot = plot_ops.select {|opt| !opt.selected?}.sample.text
          plot_dropdown.send_keys(new_plot)
        end
        # wait until violin plot renders, at this point all 3 should be done

        @wait.until {wait_for_plotly_render('#expression-plots', 'box-rendered')}
        violin_rendered = @driver.execute_script("return $('#expression-plots').data('box-rendered')")
        assert violin_rendered, "violin plot did not finish rendering, expected true but found #{violin_rendered}"
        scatter_rendered = @driver.execute_script("return $('#expression-plots').data('scatter-rendered')")
        assert scatter_rendered, "scatter plot did not finish rendering, expected true but found #{scatter_rendered}"
        reference_rendered = @driver.execute_script("return $('#expression-plots').data('reference-rendered')")
        assert reference_rendered, "reference plot did not finish rendering, expected true but found #{reference_rendered}"

        # change to box plot
        plot_dropdown = @driver.find_element(:id, 'plot_type')
        plot_ops = plot_dropdown.find_elements(:tag_name, 'option')
        new_plot = plot_ops.select {|opt| !opt.selected?}.sample.text
        plot_dropdown.send_keys(new_plot)

        # wait until box plot renders, at this point all 3 should be done
        @wait.until {wait_for_plotly_render('#expression-plots', 'box-rendered')}
        box_rendered = @driver.execute_script("return $('#expression-plots').data('box-rendered')")
        assert box_rendered, "box plot did not finish rendering, expected true but found #{box_rendered}"
        scatter_rendered = @driver.execute_script("return $('#expression-plots').data('scatter-rendered')")
        assert scatter_rendered, "scatter plot did not finish rendering, expected true but found #{scatter_rendered}"
        reference_rendered = @driver.execute_script("return $('#expression-plots').data('reference-rendered')")
        assert reference_rendered, "reference plot did not finish rendering, expected true but found #{reference_rendered}"

      else
        @wait.until {wait_for_plotly_render('#expression-plots', 'box-rendered')}
        box_rendered = @driver.execute_script("return $('#expression-plots').data('box-rendered')")
        assert box_rendered, "box plot did not finish rendering, expected true but found #{box_rendered}"
        scatter_rendered = @driver.execute_script("return $('#expression-plots').data('scatter-rendered')")
        assert scatter_rendered, "scatter plot did not finish rendering, expected true but found #{scatter_rendered}"
        reference_rendered = @driver.execute_script("return $('#expression-plots').data('reference-rendered')")
        assert reference_rendered, "reference plot did not finish rendering, expected true but found #{reference_rendered}"
      end

    end
    # now test private study
    login($test_email, $test_email_password)
    private_study_path = @base_url + "/study/private-study-#{$random_seed}"
    @driver.get private_study_path
    study_accession = extract_accession_from_url(@driver.current_url)
    loaded_private_study_path = @base_url + "/study/#{study_accession}/private-study-#{$random_seed}"
    wait_until_page_loads(loaded_private_study_path)
    open_ui_tab('study-visualize')

    new_genes = @genes.shuffle.take(rand(2..5))
    search_box = @driver.find_element(:id, 'search_genes')
    search_box.send_keys(new_genes.join(' '))

    search_menu = @driver.find_element(:id, 'search-omnibar-menu-icon')
    search_menu.click
    wait_for_render(:id, 'search_consensus')

    new_consensus = @driver.find_element(:id, 'search_consensus')

    # select a random consensus measurement
    new_opts = new_consensus.find_elements(:tag_name, 'option').delete_if {|o| o.text == 'None'}
    new_selected_consensus = new_opts.sample
    new_selected_consensus_value = new_selected_consensus['value']
    new_selected_consensus.click

    assert element_present?(:id, 'box-controls'), 'could not find expression boxplot'
    assert element_present?(:id, 'scatter-plots'), 'could not find expression scatter plots'

    # confirm queried genes are correct
    new_queried_genes = @driver.find_elements(:class, 'queried-gene').map(&:text)
    assert new_genes.sort == new_queried_genes.sort, "found incorrect genes, expected #{new_genes.sort} but found #{new_queried_genes.sort}"
    new_queried_consensus = @driver.find_element(:id, 'selected-consensus')
    assert new_selected_consensus_value == new_queried_consensus.text, "did not load correct consensus metric, expected #{new_selected_consensus_value} but found #{new_queried_consensus.text}"

    # wait until box plot renders, at this point all 3 should be done
    @wait.until {wait_for_plotly_render('#expression-plots', 'box-rendered')}
    private_violin_rendered = @driver.execute_script("return $('#expression-plots').data('box-rendered')")
    assert private_violin_rendered, "private violin plot did not finish rendering, expected true but found #{private_violin_rendered}"
    private_scatter_rendered = @driver.execute_script("return $('#expression-plots').data('scatter-rendered')")
    assert private_scatter_rendered, "private scatter plot did not finish rendering, expected true but found #{private_scatter_rendered}"
    private_reference_rendered = @driver.execute_script("return $('#expression-plots').data('reference-rendered')")
    assert private_reference_rendered, "private reference plot did not finish rendering, expected true but found #{private_reference_rendered}"

    # Open view options panel
    view_options_panel = @driver.find_element(:id, 'view-option-link')
    view_options_panel.click
    wait_for_render(:id, 'view-options')
    # open distribution control panel as well
    view_options_panel = @driver.find_element(:id, 'distribution-panel-link')
    view_options_panel.click
    wait_for_render(:id, 'distribution-plot-controls')

    # change to box plot
    private_plot_dropdown = @driver.find_element(:id, 'plot_type')
    private_plot_ops = private_plot_dropdown.find_elements(:tag_name, 'option')
    private_new_plot = private_plot_ops.select {|opt| !opt.selected?}.sample.text
    private_plot_dropdown.send_keys(private_new_plot)

    # wait until box plot renders, at this point all 3 should be done
    @wait.until {wait_for_plotly_render('#expression-plots', 'box-rendered')}
    private_box_rendered = @driver.execute_script("return $('#expression-plots').data('box-rendered')")
    assert private_box_rendered, "private box plot did not finish rendering, expected true but found #{private_box_rendered}"
    scatter_rendered = @driver.execute_script("return $('#expression-plots').data('scatter-rendered')")
    assert scatter_rendered, "private scatter plot did not finish rendering, expected true but found #{scatter_rendered}"
    reference_rendered = @driver.execute_script("return $('#expression-plots').data('reference-rendered')")
    assert reference_rendered, "private reference plot did not finish rendering, expected true but found #{reference_rendered}"

    puts "#{File.basename(__FILE__)}: '#{self.method_name}' successful!"
  end

  # search for multiple genes and view as a dot plot, and heatmap
  test 'front-end: view: search-genes: multiple dot plot heatmap' do
    puts "#{File.basename(__FILE__)}: '#{self.method_name}'"

    path = @base_url + "/study/test-study-#{$random_seed}"
    @driver.get(path)
    study_accession = extract_accession_from_url(@driver.current_url)
    loaded_path = @base_url + "/study/#{study_accession}/test-study-#{$random_seed}"
    wait_until_page_loads(loaded_path)
    open_ui_tab('study-visualize')

    # load random genes to search, take between 2-5
    genes = @genes.shuffle.take(rand(2..5))
    search_box = @driver.find_element(:id, 'search_genes')
    search_box.send_keys(genes.join(' '))
    search_genes = @driver.find_element(:id, 'perform-gene-search')
    search_genes.click

    # Verify dot plot shows by default
    wait_for_render(:id, 'dot-plot')
    assert element_present?(:id, 'plots'), 'could not find expression dot plot'
    $verbose ? puts("Verified dot plot") : nil

    # Click 'Heatmap' tab
    heatmap_tab = @driver.find_element(:id, 'plots-tab-nav')
    heatmap_tab.click
    $verbose ? puts("Clicked 'Heatmap' tab") : nil

    # Check for heatmap
    @wait.until {wait_for_morpheus_render('#heatmap-plot', 'morpheus')}
    heatmap_drawn = @driver.execute_script("return $('#heatmap-plot').data('morpheus').heatmap !== undefined;")
    assert heatmap_drawn, "heatmap plot encountered error, expected true but found #{heatmap_drawn}"
    $verbose ? puts("Verified heatmap") : nil

    view_options_panel = @driver.find_element(:id, 'view-option-link')
    view_options_panel.click
    wait_for_render(:id, 'view-options')

    annotations = @driver.find_element(:id, 'annotation').find_elements(:tag_name, 'option')
    annotations_values = annotations.map{|x| x['value']}
    annotations_values.each do |annotation|
      @driver.find_element(:id, 'annotation').send_key annotation

      # Click 'Dot plot' tab
      dot_plot_tab = @driver.find_element(:id, 'dot-tab-nav')
      dot_plot_tab.click

      # Check for dot plot
      @wait.until {wait_for_morpheus_render('#dot-plot', 'morpheus')}
      dot_plot_drawn = @driver.execute_script("return $('#dot-plot').data('morpheus').heatmap !== undefined;")
      assert dot_plot_drawn, "dot plot encountered error, expected true but found #{dot_plot_drawn}"

      # Click 'Heatmap' tab
      heatmap_tab = @driver.find_element(:id, 'plots-tab-nav')
      heatmap_tab.click

      # Check for heatmap
      @wait.until {wait_for_morpheus_render('#heatmap-plot', 'morpheus')}
      heatmap_drawn = @driver.execute_script("return $('#heatmap-plot').data('morpheus').heatmap !== undefined;")
      assert heatmap_drawn, "heatmap plot encountered error, expected true but found #{heatmap_drawn}"
    end

    heatmap_drawn = @driver.execute_script("return $('#heatmap-plot').data('morpheus').heatmap !== undefined;")
    assert heatmap_drawn, "heatmap plot encountered error, expected true but found #{heatmap_drawn}"

    # confirm queried genes are correct
    queried_genes = @driver.find_elements(:class, 'queried-gene').map(&:text)
    assert genes.sort == queried_genes.sort, "found incorrect genes, expected #{genes.sort} but found #{queried_genes.sort}"

    # resize heatmap
    scroll_to(:bottom)
    heatmap_size = @driver.find_element(:id, 'heatmap_size')
    heatmap_size.send_keys(1000)
    @wait.until {wait_for_morpheus_render('#heatmap-plot', 'morpheus')}

    resize_heatmap_drawn = @driver.execute_script("return $('#heatmap-plot').data('morpheus').heatmap !== undefined;")
    assert resize_heatmap_drawn, "heatmap plot encountered error, expected true but found #{resize_heatmap_drawn}"

    # toggle fullscreen
    fullscreen = @driver.find_element(:id, 'view-fullscreen')
    fullscreen.click
    @wait.until {wait_for_morpheus_render('#heatmap-plot', 'morpheus')}
    fullscreen_heatmap_drawn = @driver.execute_script("return $('#heatmap-plot').data('morpheus').heatmap !== undefined;")
    assert fullscreen_heatmap_drawn, "heatmap plot encountered error, expected true but found #{fullscreen_heatmap_drawn}"
    search_opts_visible = element_visible?(:id, 'search-options-panel')
    assert !search_opts_visible, "fullscreen mode did not launch correctly, expected search options visibility == false but found #{!search_opts_visible}"

    # now test private study
    login($test_email, $test_email_password)
    private_study_path = @base_url + "/study/private-study-#{$random_seed}"
    @driver.get private_study_path
    study_accession = extract_accession_from_url(@driver.current_url)
    loaded_private_study_path = @base_url + "/study/#{study_accession}/private-study-#{$random_seed}"
    wait_until_page_loads(loaded_private_study_path)
    open_ui_tab('study-visualize')

    new_genes = @genes.shuffle.take(rand(2..5))
    search_box = @driver.find_element(:id, 'search_genes')
    search_box.send_keys(new_genes.join(' '))
    search_genes = @driver.find_element(:id, 'perform-gene-search')
    search_genes.click
    assert element_present?(:id, 'plots'), 'could not find expression heatmap'
    @wait.until {wait_for_morpheus_render('#heatmap-plot', 'morpheus')}
    private_rendered = @driver.execute_script("return $('#heatmap-plot').data('rendered')")
    assert private_rendered, "private heatmap plot did not finish rendering, expected true but found #{private_rendered}"
    private_heatmap_drawn = @driver.execute_script("return $('#heatmap-plot').data('morpheus').heatmap !== undefined;")
    assert private_heatmap_drawn, "heatmap plot encountered error, expected true but found #{private_heatmap_drawn}"

    # confirm queried genes are correct
    new_queried_genes = @driver.find_elements(:class, 'queried-gene').map(&:text)
    assert new_genes.sort == new_queried_genes.sort, "found incorrect genes, expected #{new_genes.sort} but found #{new_queried_genes.sort}"

    puts "#{File.basename(__FILE__)}: '#{self.method_name}' successful!"
  end

  # search for multiple genes by uploading a text file of gene names
  test 'front-end: view: search-genes: multiple upload file' do
    puts "#{File.basename(__FILE__)}: '#{self.method_name}'"

    path = @base_url + "/study/test-study-#{$random_seed}"
    @driver.get(path)
    study_accession = extract_accession_from_url(@driver.current_url)
    loaded_path = @base_url + "/study/#{study_accession}/test-study-#{$random_seed}"
    wait_until_page_loads(loaded_path)
    open_ui_tab('study-visualize')

    search_menu = @driver.find_element(:id, 'search-omnibar-menu-icon')
    search_menu.click
    wait_for_render(:id, 'search_consensus')

    # upload gene list
    search_upload = @driver.find_element(:id, 'search_upload')
    search_upload.send_keys(@test_data_path + 'search_genes.txt')

    assert element_present?(:id, 'plots'), 'could not find expression heatmap'
    @wait.until {wait_for_morpheus_render('#heatmap-plot', 'morpheus')}
    heatmap_drawn = @driver.execute_script("return $('#heatmap-plot').data('morpheus').heatmap !== undefined;")
    assert heatmap_drawn, "heatmap plot encountered error, expected true but found #{heatmap_drawn}"

    # now test private study
    login($test_email, $test_email_password)
    private_study_path = @base_url + "/study/private-study-#{$random_seed}"
    @driver.get private_study_path
    study_accession = extract_accession_from_url(@driver.current_url)
    loaded_private_study_path = @base_url + "/study/#{study_accession}/private-study-#{$random_seed}"
    wait_until_page_loads(loaded_private_study_path)
    open_ui_tab('study-visualize')

    search_menu = @driver.find_element(:id, 'search-omnibar-menu-icon')
    search_menu.click
    wait_for_render(:id, 'search_consensus')

    search_upload = @driver.find_element(:id, 'search_upload')
    search_upload.send_keys(@test_data_path + 'search_genes.txt')

    assert element_present?(:id, 'plots'), 'could not find expression heatmap'
    @wait.until {wait_for_morpheus_render('#heatmap-plot', 'morpheus')}
    private_heatmap_drawn = @driver.execute_script("return $('#heatmap-plot').data('morpheus').heatmap !== undefined;")
    assert private_heatmap_drawn, "heatmap plot encountered error, expected true but found #{private_heatmap_drawn}"

    puts "#{File.basename(__FILE__)}: '#{self.method_name}' successful!"
  end

  # perform a global gene search for public & private studies
  test 'front-end: view: search-genes: global' do
    puts "#{File.basename(__FILE__)}: '#{self.method_name}'"

    @driver.get @base_url
    wait_until_page_loads(@base_url)
    open_ui_tab('search-genes')
    wait_for_render(:id, 'global-search-genes-form')

    gene = @genes.sample
    search_genes_form = @driver.find_element(:id, 'search_genes')
    search_genes_form.send_keys(gene)
    submit = @driver.find_element(:id, 'submit-gene-search')
    submit.click
    # wait until the plot has rendered
    panel = @driver.find_element(:xpath, "//div[@data-study='study-test-study-#{$random_seed}']")
    panel_id = panel['id']
    plot_id = panel_id + '-plot'
    counter = 0
    while !element_present?(:id, plot_id) && counter < 5
      scroll_to(:bottom) # pagination test
      sleep 5
      count += 1
    end
    @wait.until {wait_for_plotly_render('#' + plot_id, 'rendered')}
    panel_div = @driver.find_element(:id, panel_id)
    assert !panel_div.find_element(:class, 'cluster-select').nil?, 'Did not render cluster controls for gene results'
    assert !panel_div.find_element(:class, 'annotation-select').nil?, 'Did not render annotation controls for gene results'
    assert !panel_div.find_element(:class, 'subsample-select').nil?, 'Did not render subsample controls for gene results'
    # get plot data to validate violin type
    plot_data = @driver.execute_script("return document.getElementById('#{plot_id}').data")
    plot_data.each do |trace|
      assert %w(box violin).include?(trace['type']), "Incorrect plot type on trace #{trace['name']}, expected violin/box but found '#{trace['type']}'"
    end
    # load numeric annotation to test 2d scatter feature
    annotation_select = panel_div.find_element(:class, 'annotation-select')
    annotation_select.send_keys('Average Intensity')
    # wait half second for event to fire
    @wait.until {wait_for_plotly_render('#' + plot_id, 'rendered')}
    updated_data = @driver.execute_script("return document.getElementById('#{plot_id}').data")
    new_plot_type = updated_data.first['type']
    assert new_plot_type == 'scattergl', "Did not correctly update plot to 2d scatter, expected 'scattergl' but found '#{new_plot_type}'"

    # now test private data
    login($test_email, $test_email_password)
    open_ui_tab('search-genes')
    wait_for_render(:id, 'global-search-genes-form')
    second_search_genes_form = @driver.find_element(:id, 'search_genes')
    second_search_genes_form.send_keys(gene)
    submit = @driver.find_element(:id, 'submit-gene-search')
    submit.click
    while !element_present?(:id, plot_id) && counter < 5
      scroll_to(:bottom) # pagination test
      sleep 5
      count += 1
    end
    @wait.until {wait_for_plotly_render('#' + plot_id, 'rendered')}
    # wait until the plot has rendered
    private_panel = @driver.find_element(:xpath, "//div[@data-study='study-private-study-#{$random_seed}']")
    private_panel_id = private_panel['id']
    private_plot_id = private_panel_id + '-plot'
    @wait.until {wait_for_plotly_render('#' + private_plot_id, 'rendered')}
    private_panel_div = @driver.find_element(:id, private_panel_id)
    # get plot data to validate violin type
    private_plot_data = @driver.execute_script("return document.getElementById('#{private_plot_id}').data")
    private_plot_data.each do |trace|
      assert %w(box violin).include?(trace['type']), "Incorrect private plot type on trace #{trace['name']}, expected violin/box but found '#{trace['type']}'"
    end
    # load numeric annotation to test 2d scatter feature
    private_annotation_select = private_panel_div.find_element(:class, 'annotation-select')
    private_annotation_select.send_keys('Average Intensity')
    # wait half second for event to fire
    sleep(0.5)
    @wait.until {wait_for_plotly_render('#' + private_plot_id, 'rendered')}
    private_updated_data = @driver.execute_script("return document.getElementById('#{private_plot_id}').data")
    private_new_plot_type = private_updated_data.first['type']
    assert private_new_plot_type == 'scattergl', "Did not correctly update private plot to 2d scatter, expected 'scattergl' but found '#{private_new_plot_type}'"

    puts "#{File.basename(__FILE__)}: '#{self.method_name}' successful!"
  end

  # view a list of marker genes as a heatmap
  test 'front-end: view: marker-gene: heatmap' do
    puts "#{File.basename(__FILE__)}: '#{self.method_name}'"

    path = @base_url + "/study/test-study-#{$random_seed}"
    @driver.get(path)
    study_accession = extract_accession_from_url(@driver.current_url)
    loaded_path = @base_url + "/study/#{study_accession}/test-study-#{$random_seed}"
    wait_until_page_loads(loaded_path)
    open_ui_tab('study-visualize')

    search_menu = @driver.find_element(:id, 'search-omnibar-menu-icon')
    search_menu.click
    wait_for_render(:id, 'search_consensus')

    @wait.until {wait_for_plotly_render('#cluster-plot', 'rendered')}
    gene_list_panel = @driver.find_element(:id, 'gene-lists-link')
    gene_list_panel.click
    wait_for_render(:id, 'expression')
    sleep(1)

    expression_list = @driver.find_element(:id, 'expression')
    opts = expression_list.find_elements(:tag_name, 'option').delete_if {|o| o.text == 'Please select a gene list'}
    list = opts.last
    gene_list_name = list['value']
    expression_list.send_keys(gene_list_name)
    assert element_present?(:id, 'heatmap-plot'), 'could not find heatmap plot'

    # wait for heatmap to render
    @wait.until {wait_for_morpheus_render('#heatmap-plot', 'morpheus')}
    heatmap_drawn = @driver.execute_script("return $('#heatmap-plot').data('morpheus').heatmap !== undefined;")
    assert heatmap_drawn, "heatmap plot encountered error, expected true but found #{heatmap_drawn}"

    # now test private study
    login($test_email, $test_email_password)
    private_study_path = @base_url + "/study/private-study-#{$random_seed}"
    @driver.get private_study_path
    study_accession = extract_accession_from_url(@driver.current_url)
    loaded_private_study_path = @base_url + "/study/#{study_accession}/private-study-#{$random_seed}"
    wait_until_page_loads(loaded_private_study_path)
    open_ui_tab('study-visualize')

    search_menu = @driver.find_element(:id, 'search-omnibar-menu-icon')
    search_menu.click
    wait_for_render(:id, 'search_consensus')

    @wait.until {wait_for_plotly_render('#cluster-plot', 'rendered')}
    gene_list_panel = @driver.find_element(:id, 'gene-lists-link')
    gene_list_panel.click
    wait_for_render(:id, 'expression')
    sleep(1)

    private_expression_list = @driver.find_element(:id, 'expression')
    opts = private_expression_list.find_elements(:tag_name, 'option').delete_if {|o| o.text == 'Please select a gene list'}
    list = opts.last
    gene_list_name = list['value']
    private_expression_list.send_keys(gene_list_name)
    assert element_present?(:id, 'heatmap-plot'), 'could not find heatmap plot'

    # wait for heatmap to render
    @wait.until {wait_for_morpheus_render('#heatmap-plot', 'morpheus')}
    private_heatmap_drawn = @driver.execute_script("return $('#heatmap-plot').data('morpheus').heatmap !== undefined;")
    assert private_heatmap_drawn, "heatmap plot encountered error, expected true but found #{private_heatmap_drawn}"

    puts "#{File.basename(__FILE__)}: '#{self.method_name}' successful!"
  end

  # view a list of marker genes as distribution plots
  test 'front-end: view: marker-gene: box/scatter' do
    puts "#{File.basename(__FILE__)}: '#{self.method_name}'"

    path = @base_url + "/study/test-study-#{$random_seed}"
    @driver.get(path)
    study_accession = extract_accession_from_url(@driver.current_url)
    loaded_path = @base_url + "/study/#{study_accession}/test-study-#{$random_seed}"
    wait_until_page_loads(loaded_path)
    open_ui_tab('study-visualize')

    search_menu = @driver.find_element(:id, 'search-omnibar-menu-icon')
    search_menu.click
    wait_for_render(:id, 'search_consensus')

    @wait.until {wait_for_plotly_render('#cluster-plot', 'rendered')}
    gene_list_panel = @driver.find_element(:id, 'gene-lists-link')
    gene_list_panel.click
    wait_for_render(:id, 'expression')
    sleep(1)

    gene_sets = @driver.find_element(:id, 'gene_set')
    opts = gene_sets.find_elements(:tag_name, 'option').delete_if {|o| o.text == 'Please select a gene list'}
    list = opts.last
    gene_list_name = list['value']
    gene_sets.send_keys(gene_list_name)
    assert element_present?(:id, 'expression-plots'), 'could not find box/scatter divs'

    # testing loading all annotation types
    @wait.until {wait_for_plotly_render('#expression-plots', 'box-rendered')}
    view_options_panel = @driver.find_element(:id, 'view-option-link')
    view_options_panel.click
    wait_for_render(:id, 'view-options')

    # open distribution control panel as well
    view_options_panel = @driver.find_element(:id, 'distribution-panel-link')
    view_options_panel.click
    wait_for_render(:id, 'distribution-plot-controls')

    annotations = @driver.find_element(:id, 'annotation').find_elements(:tag_name, 'option')
    annotations_values = annotations.map{|x| x['value']}
    annotations_values.each do |annotation|
      @driver.find_element(:id, 'annotation').send_key annotation
      type = annotation.split('--')[1]
      $verbose ? puts( "loading annotation: #{annotation}") : nil
      if type == 'group'
        # if looking at box, switch back to violin
        @wait.until {wait_for_plotly_render('#expression-plots', 'box-rendered')}
        plot_dropdown = @driver.find_element(:id, 'plot_type')
        plot_ops = plot_dropdown.find_elements(:tag_name, 'option')

        is_box_plot = plot_ops.select {|opt| opt.selected?}.sample.text == 'Box Plot'
        if is_box_plot
          new_plot = plot_ops.select {|opt| !opt.selected?}.sample.text
          plot_dropdown.send_keys(new_plot)
        end
        # wait until violin plot renders, at this point all 3 should be done

        @wait.until {wait_for_plotly_render('#expression-plots', 'box-rendered')}
        violin_rendered = @driver.execute_script("return $('#expression-plots').data('box-rendered')")
        assert violin_rendered, "violin plot did not finish rendering, expected true but found #{violin_rendered}"
        scatter_rendered = @driver.execute_script("return $('#expression-plots').data('scatter-rendered')")
        assert scatter_rendered, "scatter plot did not finish rendering, expected true but found #{scatter_rendered}"
        reference_rendered = @driver.execute_script("return $('#expression-plots').data('reference-rendered')")
        assert reference_rendered, "reference plot did not finish rendering, expected true but found #{reference_rendered}"

        # change to box plot
        plot_dropdown = @driver.find_element(:id, 'plot_type')
        plot_ops = plot_dropdown.find_elements(:tag_name, 'option')
        new_plot = plot_ops.select {|opt| !opt.selected?}.sample.text
        plot_dropdown.send_keys(new_plot)

        # wait until box plot renders, at this point all 3 should be done
        @wait.until {wait_for_plotly_render('#expression-plots', 'box-rendered')}
        box_rendered = @driver.execute_script("return $('#expression-plots').data('box-rendered')")
        assert box_rendered, "box plot did not finish rendering, expected true but found #{box_rendered}"
        scatter_rendered = @driver.execute_script("return $('#expression-plots').data('scatter-rendered')")
        assert scatter_rendered, "scatter plot did not finish rendering, expected true but found #{scatter_rendered}"
        reference_rendered = @driver.execute_script("return $('#expression-plots').data('reference-rendered')")
        assert reference_rendered, "reference plot did not finish rendering, expected true but found #{reference_rendered}"

      else
        @wait.until {wait_for_plotly_render('#expression-plots', 'box-rendered')}
        box_rendered = @driver.execute_script("return $('#expression-plots').data('box-rendered')")
        assert box_rendered, "box plot did not finish rendering, expected true but found #{box_rendered}"
        scatter_rendered = @driver.execute_script("return $('#expression-plots').data('scatter-rendered')")
        assert scatter_rendered, "scatter plot did not finish rendering, expected true but found #{scatter_rendered}"
        reference_rendered = @driver.execute_script("return $('#expression-plots').data('reference-rendered')")
        assert reference_rendered, "reference plot did not finish rendering, expected true but found #{reference_rendered}"
      end

    end

    # now test private study
    login($test_email, $test_email_password)
    private_study_path = @base_url + "/study/private-study-#{$random_seed}"
    @driver.get private_study_path
    study_accession = extract_accession_from_url(@driver.current_url)
    loaded_private_study_path = @base_url + "/study/#{study_accession}/private-study-#{$random_seed}"
    wait_until_page_loads(loaded_private_study_path)
    open_ui_tab('study-visualize')

    search_menu = @driver.find_element(:id, 'search-omnibar-menu-icon')
    search_menu.click
    wait_for_render(:id, 'search_consensus')

    @wait.until {wait_for_plotly_render('#cluster-plot', 'rendered')}
    gene_list_panel = @driver.find_element(:id, 'gene-lists-link')
    gene_list_panel.click
    wait_for_render(:id, 'expression')
    sleep(1)

    private_gene_sets = @driver.find_element(:id, 'gene_set')
    opts = private_gene_sets.find_elements(:tag_name, 'option').delete_if {|o| o.text == 'Please select a gene list'}
    list = opts.last
    gene_list_name = list['value']
    private_gene_sets.send_keys(gene_list_name)
    assert element_present?(:id, 'expression-plots'), 'could not find box/scatter divs'

    # wait until box plot renders, at this point all 3 should be done
    @wait.until {wait_for_plotly_render('#expression-plots', 'box-rendered')}
    private_violin_rendered = @driver.execute_script("return $('#expression-plots').data('box-rendered')")
    assert private_violin_rendered, "private violin plot did not finish rendering, expected true but found #{private_violin_rendered}"
    private_scatter_rendered = @driver.execute_script("return $('#expression-plots').data('scatter-rendered')")
    assert private_scatter_rendered, "private scatter plot did not finish rendering, expected true but found #{private_scatter_rendered}"
    private_reference_rendered = @driver.execute_script("return $('#expression-plots').data('reference-rendered')")
    assert private_reference_rendered, "private reference plot did not finish rendering, expected true but found #{private_reference_rendered}"

    # change to box plot
    view_options_panel = @driver.find_element(:id, 'view-option-link')
    view_options_panel.click
    dist_panel = @driver.find_element(:id, 'distribution-panel-link')
    dist_panel.click
    wait_for_render(:id, 'distribution-plot-controls')
    private_plot_dropdown = @driver.find_element(:id, 'plot_type')
    private_plot_ops = private_plot_dropdown.find_elements(:tag_name, 'option')
    private_new_plot = private_plot_ops.select {|opt| !opt.selected?}.sample.text
    private_plot_dropdown.send_keys(private_new_plot)

    # wait until box plot renders, at this point all 3 should be done
    @wait.until {wait_for_plotly_render('#expression-plots', 'box-rendered')}
    private_box_rendered = @driver.execute_script("return $('#expression-plots').data('box-rendered')")
    assert private_box_rendered, "private box plot did not finish rendering, expected true but found #{private_box_rendered}"
    scatter_rendered = @driver.execute_script("return $('#expression-plots').data('scatter-rendered')")
    assert scatter_rendered, "private scatter plot did not finish rendering, expected true but found #{scatter_rendered}"
    reference_rendered = @driver.execute_script("return $('#expression-plots').data('reference-rendered')")
    assert reference_rendered, "private reference plot did not finish rendering, expected true but found #{reference_rendered}"

    puts "#{File.basename(__FILE__)}: '#{self.method_name}' successful!"
  end

  ##
  ## FRONT-END VALIDATION TESTS
  ## Tests statefulness of views when switching back and forth between plots and editing study defaults,
  ## as well as validations for bespoke visualizations
  ##

  # tests that form values for loaded clusters & annotations are being persisted when switching between different views and using 'back' button in search box
  test 'front-end: validation: cluster and annotation persistence' do
    puts "#{File.basename(__FILE__)}: '#{self.method_name}'"

    path = @base_url + "/study/test-study-#{$random_seed}"
    @driver.get(path)
    study_accession = extract_accession_from_url(@driver.current_url)
    loaded_path = @base_url + "/study/#{study_accession}/test-study-#{$random_seed}"
    wait_until_page_loads(loaded_path)
    open_ui_tab('study-visualize')

    @wait.until {wait_for_plotly_render('#cluster-plot', 'rendered')}
    view_options_panel = @driver.find_element(:id, 'view-option-link')
    view_options_panel.click
    wait_for_render(:id, 'view-options')
    clusters = @driver.find_element(:id, 'cluster').find_elements(:tag_name, 'option')
    cluster = clusters.last
    cluster_name = cluster['text']
    cluster.click

    # wait for render to complete
    @wait.until {wait_for_plotly_render('#cluster-plot', 'rendered')}
    cluster_rendered = @driver.execute_script("return $('#cluster-plot').data('rendered')")
    assert cluster_rendered, "cluster plot did not finish rendering on cluster change, expected true but found #{cluster_rendered}"

    # select an annotation and wait for render
    annotations = @driver.find_element(:id, 'annotation').find_elements(:tag_name, 'option')
    annotation = annotations.sample
    annotation_value = annotation['value']
    annotation.click
    $verbose ? puts( "Using annotation #{annotation_value}") : nil
    @wait.until {wait_for_plotly_render('#cluster-plot', 'rendered')}
    annot_rendered = @driver.execute_script("return $('#cluster-plot').data('rendered')")
    assert annot_rendered, "cluster plot did not finish rendering on annotation change, expected true but found #{annot_rendered}"

    # now search for a gene and make sure values are preserved
    gene = @genes.sample
    search_box = @driver.find_element(:id, 'search_genes')
    search_box.send_keys(gene)
    search_genes = @driver.find_element(:id, 'perform-gene-search')
    search_genes.click

    # wait for rendering to complete
    assert element_present?(:id, 'expression-plots'), 'could not find box/scatter divs'

    @wait.until {wait_for_plotly_render('#expression-plots', 'box-rendered')}
    violin_rendered = @driver.execute_script("return $('#expression-plots').data('box-rendered')")
    assert violin_rendered, "box plot did not finish rendering, expected true but found #{violin_rendered}"
    scatter_rendered = @driver.execute_script("return $('#expression-plots').data('scatter-rendered')")
    assert scatter_rendered, "scatter plot did not finish rendering, expected true but found #{scatter_rendered}"
    reference_rendered = @driver.execute_script("return $('#expression-plots').data('reference-rendered')")
    assert reference_rendered, "reference plot did not finish rendering, expected true but found #{reference_rendered}"

    # now check values
    loaded_cluster = @driver.find_element(:id, 'cluster')
    loaded_annotation = @driver.find_element(:id, 'annotation')
    assert loaded_cluster['value'] == cluster_name, "did not load correct cluster; expected #{cluster_name} but loaded #{loaded_cluster['value']}"
    assert loaded_annotation['value'] == annotation_value, "did not load correct annotation; expected #{annotation_value} but loaded #{loaded_annotation['value']}"

    # now check the back button in the search box to make sure it preserves values
    search_menu = @driver.find_element(:id, 'search-omnibar-menu-icon')
    search_menu.click
    wait_for_render(:id, 'search_consensus')
    back_btn = @driver.find_element(:id, 'clear-gene-search')
    back_btn.click
    @wait.until {wait_for_plotly_render('#cluster-plot', 'rendered')}
    sleep(1)

    current_cluster = @driver.find_element(:id, 'cluster')
    current_annotation = @driver.find_element(:id, 'annotation')
    assert current_cluster['value'] == cluster_name, "did not load correct cluster after back button; expected #{cluster_name} but loaded #{current_cluster['value']}"
    assert current_annotation['value'] == annotation_value, "did not load correct annotation after back button; expected #{current_annotation} but loaded #{current_annotation['value']}"

    # now search for multiple genes as a heatmap
    genes = @genes.shuffle.take(rand(2..5))
    search_box = @driver.find_element(:id, 'search_genes')
    search_box.send_keys(genes.join(' '))
    search_genes = @driver.find_element(:id, 'perform-gene-search')
    search_genes.click
    assert element_present?(:id, 'plots'), 'could not find expression heatmap'
    @wait.until {wait_for_morpheus_render('#heatmap-plot', 'morpheus')}

    # click back button in search box
    back_btn = @driver.find_element(:id, 'clear-gene-search')
    back_btn.click
    @wait.until {wait_for_plotly_render('#cluster-plot', 'rendered')}

    heatmap_cluster =  @driver.find_element(:id, 'cluster')['value']
    heatmap_annot = @driver.find_element(:id, 'annotation')['value']
    assert heatmap_cluster == cluster_name, "cluster was not preserved correctly from heatmap view, expected #{cluster_name} but found #{heatmap_cluster}"
    assert heatmap_annot == annotation_value, "cluster was not preserved correctly from heatmap view, expected #{annotation_value} but found #{heatmap_annot}"

    # show gene list in scatter mode
    gene_list_panel = @driver.find_element(:id, 'gene-lists-link')
    gene_list_panel.click
    wait_for_render(:id, 'expression')
    sleep(0.5)

    gene_sets = @driver.find_element(:id, 'gene_set')
    opts = gene_sets.find_elements(:tag_name, 'option').delete_if {|o| o.text == 'Please select a gene list'}
    list = opts.last
    gene_list_name = list['value']
    gene_sets.send_keys(gene_list_name)

    assert element_present?(:id, 'expression-plots'), 'could not find box/scatter divs'
    @wait.until {wait_for_plotly_render('#expression-plots', 'box-rendered')}

    # click back button in search box
    back_btn = @driver.find_element(:id, 'clear-gene-search')
    back_btn.click
    @wait.until {wait_for_plotly_render('#cluster-plot', 'rendered')}

    gene_list_cluster =  @driver.find_element(:id, 'cluster')['value']
    gene_list_annot = @driver.find_element(:id, 'annotation')['value']
    assert gene_list_cluster == cluster_name, "cluster was not preserved correctly from gene list scatter view, expected #{cluster_name} but found #{gene_list_cluster}"
    assert gene_list_annot == annotation_value, "cluster was not preserved correctly from gene list scatter view, expected #{gene_list_annot} but found #{heatmap_annot}"

    puts "#{File.basename(__FILE__)}: '#{self.method_name}' successful!"
  end

  # REMOVED scatter plot camera test as manually calling Plotly.relayout does not emit the event

  # change the default study options and verify they are being preserved across views
  # this is a blend of admin and front-end tests and is run last as has the potential to break previous tests
  test 'front-end: validation: study default options' do
    puts "#{File.basename(__FILE__)}: '#{self.method_name}'"

    @driver.get @base_url
    login($test_email, $test_email_password)
    path = @base_url + '/studies'
    @driver.get path

    show_study = @driver.find_element(:class, "test-study-#{$random_seed}-show")
    show_study.click

    # change cluster
    options_form = @driver.find_element(:id, 'default-study-options-form')
    cluster_dropdown = options_form.find_element(:id, 'study_default_options_cluster')
    cluster_opts = cluster_dropdown.find_elements(:tag_name, 'option')
    new_cluster = cluster_opts.select {|opt| !opt.selected?}.sample.text
    cluster_dropdown.send_keys(new_cluster)

    # wait one second while annotation options update
    sleep(1)

    # change annotation
    annotation_dropdown = options_form.find_element(:id, 'study_default_options_annotation')
    annotation_opts = annotation_dropdown.find_elements(:tag_name, 'option')
    # get value, not text, of dropdown
    new_annot = annotation_opts.select {|opt| !opt.selected?}.sample['value']
    annotation_dropdown.send_keys(new_annot)

    # if annotation option is now numeric, pick a color val
    new_color = ''
    color_dropdown = options_form.find_element(:id, 'study_default_options_color_profile')
    if color_dropdown['disabled'] != 'true'
      color_opts = color_dropdown.find_elements(:tag_name, 'option')
      new_color = color_opts.select {|opt| !opt.selected?}.sample.text
      color_dropdown.send_keys(new_color)
    end

    # change expression axis label
    expression_label = options_form.find_element(:id, 'study_default_options_expression_label')
    new_exp_label = 'Gene Expression Scores'
    expression_label.clear
    expression_label.send_keys(new_exp_label)

    # change cluster point size, turn off borders, and reduce alpha
    cluster_point_size = options_form.find_element(:id, 'study_default_options_cluster_point_size')
    cluster_point_size.clear
    cluster_point_size.send_keys(8)
    cluster_borders = options_form.find_element(:id, 'study_default_options_cluster_point_border')
    cluster_borders.send_keys('No')
    cluster_alpha = options_form.find_element(:id, 'study_default_options_cluster_point_alpha')
    cluster_alpha.clear
    cluster_alpha.send_keys(0.5)

    # save options
    options_form.submit
    close_modal('study-file-notices')

    study_page = @base_url + "/study/test-study-#{$random_seed}"
    @driver.get study_page
    @wait.until {wait_for_plotly_render('#cluster-plot', 'rendered')}
    open_ui_tab('study-visualize')

    # assert values have persisted
    loaded_cluster = @driver.find_element(:id, 'cluster')['value']
    loaded_annotation = @driver.find_element(:id, 'annotation')['value']
    cluster_point_size = @driver.execute_script("return data[0].marker.size;")
    cluster_border = @driver.execute_script("return data[0].marker.line.width;").to_f
    cluster_alpha_val = @driver.execute_script("return data[0].opacity;").to_f
    assert new_cluster == loaded_cluster, "default cluster incorrect, expected #{new_cluster} but found #{loaded_cluster}"
    assert new_annot == loaded_annotation, "default annotation incorrect, expected #{new_annot} but found #{loaded_annotation}"
    assert cluster_point_size == 8, "default cluster point size incorrect, expected 8 but found #{cluster_point_size}"
    assert cluster_border == 0.0, "default cluster border incorrect, expected 0.0 but found #{cluster_border}"
    assert cluster_alpha_val == 0.5, "default cluster alpha incorrect, expected 0.5 but found #{cluster_alpha_val}"
    unless new_color.empty?
      loaded_color = @driver.find_element(:id, 'colorscale')['value']
      assert new_color == loaded_color, "default color incorrect, expected #{new_color} but found #{loaded_color}"
    end

    # now check gene expression pages
    gene = @genes.sample
    search_box = @driver.find_element(:id, 'search_genes')
    search_box.send_keys(gene)
    search_genes = @driver.find_element(:id, 'perform-gene-search')
    search_genes.click
    @wait.until {wait_for_plotly_render('#expression-plots', 'box-rendered')}

    exp_loaded_cluster = @driver.find_element(:id, 'cluster')['value']
    exp_loaded_annotation = @driver.find_element(:id, 'annotation')['value']
    # open scatter tab
    scatter_link = @driver.find_element(:id, 'scatter-link')
    scatter_link.click
    wait_for_render(:id, 'scatter-plots')
    exp_loaded_label = @driver.find_element(:class, 'cbtitle').text
    assert new_cluster == exp_loaded_cluster, "default cluster incorrect, expected #{new_cluster} but found #{exp_loaded_cluster}"
    assert new_annot == exp_loaded_annotation, "default annotation incorrect, expected #{new_annot} but found #{exp_loaded_annotation}"
    assert exp_loaded_label == new_exp_label, "default expression label incorrect, expected #{new_exp_label} but found #{exp_loaded_label}"

    unless new_color.empty?
      exp_loaded_color = @driver.find_element(:id, 'colorscale')['value']
      assert new_color == exp_loaded_color, "default color incorrect, expected #{new_color} but found #{exp_loaded_color}"
    end

    # now update the name of the default cluster to make sure it saves
    path = @base_url + '/studies'
    @driver.get path

    edit_study_data = @driver.find_element(:class, "test-study-#{$random_seed}-upload")
    edit_study_data.click
    cluster_tab = @driver.find_element(:id, 'initialize_ordinations_form_nav')
    cluster_tab.click
    cluster_forms = @driver.find_elements(:class, 'initialize_ordinations_form')
    cluster_forms.each do |form|
      cluster_name = form.find_element(:id, 'study_file_name')
      if cluster_name['value'] == new_cluster
        cluster_name.send_keys(" (#{$random_seed})")
        save_btn = form.find_element(:class, 'save-study-file')
        save_btn.click
        close_modal('study-file-notices')
      end
    end

    # validate update was persisted
    @driver.get path
    show_study = @driver.find_element(:class, "test-study-#{$random_seed}-show")
    show_study.click
    options_form = @driver.find_element(:id, 'default-study-options-form')
    cluster_dropdown = options_form.find_element(:id, 'study_default_options_cluster')
    new_default_cluster = cluster_dropdown.find_elements(:tag_name, 'option').detect {|opt| opt.selected?}
    expected_name = new_cluster + " (#{$random_seed})"
    assert new_default_cluster.text == expected_name, "Did not update default cluster: #{expected_name} does not equal #{new_default_cluster.text}"

    # make sure front end reflects change
    study_page = @base_url + "/study/test-study-#{$random_seed}"
    @driver.get study_page
    study_accession = extract_accession_from_url(@driver.current_url)
    loaded_path = @base_url + "/study/#{study_accession}/test-study-#{$random_seed}"
    wait_until_page_loads(loaded_path)
    open_ui_tab('study-visualize')
    view_options_panel = @driver.find_element(:id, 'view-option-link')
    view_options_panel.click
    wait_for_render(:id, 'view-options')
    selected_cluster = @driver.find_element(:id, 'cluster')
    assert selected_cluster['value'] == expected_name, "Front end did not update default cluster: #{selected_cluster['value']} does not equal #{expected_name}"

    puts "#{File.basename(__FILE__)}: '#{self.method_name}' successful!"
  end

  # update a study via the study settings panel
  test 'front-end: validation: edit study settings' do
    puts "#{File.basename(__FILE__)}: '#{self.method_name}'"

    @driver.get @base_url
    login($test_email, $test_email_password)

    study_page = @base_url + "/study/test-study-#{$random_seed}"
    @driver.get study_page
    study_accession = extract_accession_from_url(@driver.current_url)
    loaded_path = @base_url + "/study/#{study_accession}/test-study-#{$random_seed}"
    wait_until_page_loads(loaded_path)

    # update description first
    edit_btn = @driver.find_element(:id, 'edit-study-description')
    edit_btn.click
    wait_for_render(:id, 'update-study-description')
    description = @driver.find_element(:class, 'ck-editor__editable')
    random = SecureRandom.uuid
    new_description = "This is the description with a random element: #{random}."
    description.send_keys(new_description)
    update_btn = @driver.find_element(:id, 'update-study-description')
    update_btn.click
    wait_for_render(:id, 'edit-study-description')

    study_description = @driver.find_element(:id, 'study-description-content')
    updated_text = study_description.text
    assert updated_text.include?(new_description), "study description did not update correctly, expected #{new_description} but found #{updated_text}"

    # update default options
    close_modal('message_modal')
    open_ui_tab('study-settings')
    options_form = @driver.find_element(:id, 'default-study-options-form')
    cluster_dropdown = options_form.find_element(:id, 'study_default_options_cluster')
    cluster_opts = cluster_dropdown.find_elements(:tag_name, 'option')
    new_cluster = cluster_opts.select {|opt| !opt.selected?}.sample.text
    cluster_dropdown.send_keys(new_cluster)
    # change cluster point size, turn on borders, and reset alpha
    cluster_point_size = options_form.find_element(:id, 'study_default_options_cluster_point_size')
    cluster_point_size.clear
    cluster_point_size.send_keys(6)
    cluster_borders = options_form.find_element(:id, 'study_default_options_cluster_point_border')
    cluster_borders.send_keys('Yes')
    cluster_alpha = options_form.find_element(:id, 'study_default_options_cluster_point_alpha')
    cluster_alpha.clear
    cluster_alpha.send_keys(1)

    # wait one second while annotation options update
    sleep(1)

    # change annotation
    annotation_dropdown = options_form.find_element(:id, 'study_default_options_annotation')
    annotation_opts = annotation_dropdown.find_elements(:tag_name, 'option')
    # get value, not text, of dropdown
    new_annot = annotation_opts.select {|opt| !opt.selected?}.sample['value']
    annotation_dropdown.send_keys(new_annot)

    # if annotation option is now numeric, pick a color val
    new_color = ''
    color_dropdown = options_form.find_element(:id, 'study_default_options_color_profile')
    if color_dropdown['disabled'] != 'true'
      color_opts = color_dropdown.find_elements(:tag_name, 'option')
      new_color = color_opts.select {|opt| !opt.selected?}.sample.text
      color_dropdown.send_keys(new_color)
    end

    # set cell count
    new_cells = rand(100) + 1
    cell_count = @driver.find_element(:id, 'study_cell_count')
    cell_count.clear
    cell_count.send_keys(new_cells)

    # manually set rendered to false to avoid a race condition when checking for updates
    @driver.execute_script("$('#cluster-plot').data('rendered', false);")
    # now save changes
    update_btn = @driver.find_element(:id, 'update-study-settings')
    update_btn.click
    close_modal('message_modal')
    @wait.until {wait_for_plotly_render('#cluster-plot', 'rendered')}

    # assert values have persisted
    open_ui_tab('study-visualize')
    loaded_cluster = @driver.find_element(:id, 'cluster')['value']
    loaded_annotation = @driver.find_element(:id, 'annotation')['value']
    cluster_point_size = @driver.execute_script("return data[0].marker.size;")
    cluster_border = @driver.execute_script("return data[0].marker.line.width;").to_f
    cluster_alpha_val = @driver.execute_script("return data[0].opacity;").to_f
    assert new_cluster == loaded_cluster, "default cluster incorrect, expected #{new_cluster} but found #{loaded_cluster}"
    assert new_annot == loaded_annotation, "default annotation incorrect, expected #{new_annot} but found #{loaded_annotation}"
    assert cluster_point_size == 6, "default cluster point size incorrect, expected 8 but found #{cluster_point_size}"
    assert cluster_border == 0.5, "default cluster border incorrect, expected 0.0 but found #{cluster_border}"
    assert cluster_alpha_val == 1.0, "default cluster alpha incorrect, expected 0.5 but found #{cluster_alpha_val}"

    unless new_color.empty?
      loaded_color = @driver.find_element(:id, 'colorscale')['value']
      assert new_color == loaded_color, "default color incorrect, expected #{new_color} but found #{loaded_color}"
    end
    new_cell_count = @driver.find_element(:id, 'cell-count').text.split.first.to_i
    assert new_cell_count == new_cells, "cell count did not update, expected #{new_cells} but found #{new_cell_count}"

    # now test if auth challenge is working properly using test study
    open_new_page(@base_url)
    logout_from_portal

    # check authentication challenge
    @driver.switch_to.window(@driver.window_handles.first)
    sleep(1)
    open_ui_tab('study-settings')
    public_dropdown = @driver.find_element(:id, 'study_public')
    public_dropdown.send_keys('Yes')
    update_btn = @driver.find_element(:id, 'update-study-settings')
    update_btn.click
    wait_for_modal_open('message_modal')
    alert_text = @driver.find_element(:id, 'alert-content').text
    assert alert_text == "We're sorry, but the change you wanted was rejected by the server.", "incorrect alert text - expected 'We're sorry, but the change you wanted was rejected by the server' but found #{alert_text}"
    close_modal('message_modal')

    puts "#{File.basename(__FILE__)}: '#{self.method_name}' successful!"
  end

  ##
  ## USER ANNOTATION TESTS
  ## Tests CRUDing UserAnnotation objects, as well as sharing and publishing
  ##

  # Create a user annotation
  test 'front-end: user-annotation: creation' do
    puts "#{File.basename(__FILE__)}: '#{self.method_name}'"

    # log in
    @driver.get @base_url
    login($test_email, $test_email_password)

    # first confirm that you cannot create an annotation on a 3d study
    test_study_path = @base_url + "/study/test-study-#{$random_seed}"
    @driver.get test_study_path
    study_accession = extract_accession_from_url(@driver.current_url)
    loaded_path = @base_url + "/study/#{study_accession}/test-study-#{$random_seed}"
    wait_until_page_loads(loaded_path)
    open_ui_tab('study-visualize')
    @wait.until {wait_for_plotly_render('#cluster-plot', 'rendered')}
    search_menu = @driver.find_element(:id, 'search-omnibar-menu-icon')
    search_menu.click
    wait_for_render(:id, 'search_consensus')
    select_dropdown = @driver.find_element(:id, 'create_annotations_panel')
    select_dropdown.click
    # let collapse animation complete
    sleep(2)
    enable_select_button = @driver.find_element(:id, 'toggle-scatter')
    enable_select_button.click
    alert = @driver.switch_to.alert
    alert_text = alert.text
    assert alert_text == 'You may not create annotations on 3d data.  Please select a different cluster before continuing.',
           "did not find correct alert, expected 'You may not create annotations on 3d data.  Please select a different cluster before continuing.' but found '#{}'"
    alert.accept

    # go to the 2d scatter plot study
    two_d_study_path = @base_url + "/study/twod-study-#{$random_seed}"
    @driver.get two_d_study_path
    study_accession = extract_accession_from_url(@driver.current_url)
    loaded_2d_path = @base_url + "/study/#{study_accession}/twod-study-#{$random_seed}"
    wait_until_page_loads(loaded_2d_path)
    open_ui_tab('study-visualize')

    # Click selection tab
    search_menu = @driver.find_element(:id, 'search-omnibar-menu-icon')
    search_menu.click
    wait_for_render(:id, 'search_consensus')
    select_dropdown = @driver.find_element(:id, 'create_annotations_panel')
    select_dropdown.click
    # let collapse animation complete
    sleep(2)

    # Enable Selection
    wait_for_render(:id, 'toggle-scatter')
    enable_select_button = @driver.find_element(:id, 'toggle-scatter')
    enable_select_button.click
    # let plot redraw
    wait_for_render(:id, 'selection-well')

    # click box select button
    select_button = @driver.find_element(:xpath, "//a[@data-val='select']")
    select_button.click
    assert select_button['class'] == 'modebar-btn active', "Did not properly select box mode, expected class value of 'modebar-btn active' but found #{select_button['class']}"

    # calculate the position of the plot and perform the click & drag event (move by 25% of plot size down & right)
    plot = @driver.find_element(:id, 'cluster-plot')
    @driver.action.move_to(plot, plot.size.width / 4, plot.size.height / 4 ).click_and_hold.perform
    @driver.action.move_by(plot.size.width / 4 , plot.size.height / 4).release.perform

    # send the keys for the name of the annotation
    annotation_name = @driver.find_element(:class, 'annotation-name')
    name = "user-#{$random_seed}"
    annotation_name.send_keys(name)

    # make sure we have two classes now
    annotation_labels = @driver.find_elements(:class, 'annotation-label')
    assert annotation_labels.size == 2, "Did not find correct number of annotation label fields, expecte 2 but found #{annotation_labels.size}"
    # send keys to the labels of the annotation

    annotation_labels.each_with_index do |annot, i|
      annot.send_keys("group#{i}")
    end

    # create the annotation
    submit_button = @driver.find_element(:id, 'selection-submit')
    submit_button.click

    close_modal('message_modal')

    # choose the user annotation
    view_options_panel = @driver.find_element(:id, 'view-option-link')
    view_options_panel.click
    wait_for_render(:id, 'view-options')

    annotation_dropdown = @driver.find_element(:id, 'annotation')
    annotation_dropdown.send_keys("user-#{$random_seed}")
    @wait.until {wait_for_plotly_render('#cluster-plot', 'rendered')}

    # make sure the new annotation still renders a plot for plotly
    annot_rendered = @driver.execute_script("return $('#cluster-plot').data('rendered')")
    assert annot_rendered, "cluster plot did not finish rendering on annotation change, expected true but found #{annot_rendered}"

    @driver.find_element(:id, 'search-genes-link').click
    wait_for_render(:id, 'search-genes-form')

    # load random gene to search
    scroll_to(:top)
    gene = @genes.sample
    search_box = @driver.find_element(:id, 'search_genes')
    search_box.send_keys(gene)
    search_genes = @driver.find_element(:id, 'perform-gene-search')
    search_genes.click

    # make sure the new annotation still renders plots for plotly
    assert element_present?(:id, 'box-controls'), 'could not find expression violin plot'
    assert element_present?(:id, 'scatter-plots'), 'could not find expression scatter plots'

    # confirm queried gene is the one returned
    queried_gene = @driver.find_element(:class, 'queried-gene')
    assert queried_gene.text == gene, "did not load the correct gene, expected #{gene} but found #{queried_gene.text}"

    # wait until violin plot renders, at this point all 3 should be done
    @wait.until {wait_for_plotly_render('#expression-plots', 'box-rendered')}
    violin_rendered = @driver.execute_script("return $('#expression-plots').data('box-rendered')")
    assert violin_rendered, "violin plot did not finish rendering, expected true but found #{violin_rendered}"
    scatter_rendered = @driver.execute_script("return $('#expression-plots').data('scatter-rendered')")
    assert scatter_rendered, "scatter plot did not finish rendering, expected true but found #{scatter_rendered}"
    reference_rendered = @driver.execute_script("return $('#expression-plots').data('reference-rendered')")
    assert reference_rendered, "reference plot did not finish rendering, expected true but found #{reference_rendered}"

    # change to box plot
    plot_dropdown = @driver.find_element(:id, 'plot_type')
    plot_ops = plot_dropdown.find_elements(:tag_name, 'option')
    new_plot = plot_ops.select {|opt| !opt.selected?}.sample.text
    plot_dropdown.send_keys(new_plot)

    # wait until box plot renders, at this point all 3 should be done
    @wait.until {wait_for_plotly_render('#expression-plots', 'box-rendered')}
    box_rendered = @driver.execute_script("return $('#expression-plots').data('box-rendered')")
    assert box_rendered, "box plot did not finish rendering, expected true but found #{box_rendered}"
    scatter_rendered = @driver.execute_script("return $('#expression-plots').data('scatter-rendered')")
    assert scatter_rendered, "scatter plot did not finish rendering, expected true but found #{scatter_rendered}"
    reference_rendered = @driver.execute_script("return $('#expression-plots').data('reference-rendered')")
    assert reference_rendered, "reference plot did not finish rendering, expected true but found #{reference_rendered}"

    gene_list_panel = @driver.find_element(:id, 'gene-lists-link')
    gene_list_panel.click
    wait_for_render(:id, 'expression')
    sleep(1)
    gene_sets = @driver.find_element(:id, 'gene_set')
    opts = gene_sets.find_elements(:tag_name, 'option').delete_if {|o| o.text == 'Please select a gene list'}
    list = opts.last
    gene_list_name = list['value']
    gene_sets.send_keys(gene_list_name)

    # wait until violin plot renders, at this point all 3 should be done
    @wait.until {wait_for_plotly_render('#expression-plots', 'box-rendered')}
    @wait.until {wait_for_plotly_render('#expression-plots', 'scatter-rendered')}
    violin_rendered = @driver.execute_script("return $('#expression-plots').data('box-rendered')")
    assert violin_rendered, "violin plot did not finish rendering, expected true but found #{violin_rendered}"
    scatter_rendered = @driver.execute_script("return $('#expression-plots').data('scatter-rendered')")
    assert scatter_rendered, "scatter plot did not finish rendering, expected true but found #{scatter_rendered}"
    reference_rendered = @driver.execute_script("return $('#expression-plots').data('reference-rendered')")
    assert reference_rendered, "reference plot did not finish rendering, expected true but found #{reference_rendered}"

    # Create an annotation from the gene page.  Due to the size of rendered elements, the only reproducible way to click the
    # annotation selection button is to scroll to the top, close the search panel, and open the annotation panel
    scroll_to(:top)
    # open scatter tab
    scatter_link = @driver.find_element(:id, 'scatter-link')
    scatter_link.click
    wait_for_render(:id, 'scatter-plots')

    # Click selection tabs
    select_dropdown = @driver.find_element(:id, 'create_annotations_panel')
    select_dropdown.click
    # let collapse animation complete
    sleep(2)
    # Enable Selection
    enable_select_button = @driver.find_element(:id, 'toggle-scatter')
    enable_select_button.click
    wait_for_render(:id, 'selection-well')

    # click box select button
    scroll_to(:bottom)
    select_button = @driver.find_element(:xpath, "//div[@id='scatter-plot']//a[@data-val='select']")
    select_button.click
    assert select_button['class'] == 'modebar-btn active', "Did not properly select box mode, expected class value of 'modebar-btn active' but found #{select_button['class']}"


    # calculate the position of the plot and perform the click & drag event (move by 25% down & right)
    plot = @driver.find_element(:id, 'scatter-plot')
    @driver.action.move_to(plot, plot.size.width / 4, plot.size.height / 4 ).click_and_hold.perform
    @driver.action.move_by(plot.size.width / 4 , plot.size.height / 4).release.perform

    # send the keys for the name of the annotation
    annotation_name = @driver.find_element(:class, 'annotation-name')
    name = "user-#{$random_seed}-exp"
    annotation_name.send_keys(name)

    # make sure we have two classes now
    annotation_labels = @driver.find_elements(:class, 'annotation-label')
    assert annotation_labels.size == 2, "Did not find correct number of annotation label fields, expecte 2 but found #{annotation_labels.size}"

    # send keys to the labels of the annotation
    annotation_labels.each_with_index do |annot, i|
      annot.send_keys("group#{i}")
    end

    # create the annotation
    submit_button = @driver.find_element(:id, 'selection-submit')
    submit_button.click

    close_modal('message_modal')

    @driver.get loaded_2d_path
    wait_until_page_loads(loaded_2d_path)
    open_ui_tab('study-visualize')

    # choose the user annotation
    @wait.until {wait_for_plotly_render('#cluster-plot', 'rendered')}

    view_options_panel = @driver.find_element(:id, 'view-option-link')
    view_options_panel.click
    wait_for_render(:id, 'view-options')

    annotation_dropdown = @driver.find_element(:id, 'annotation')
    annotation_dropdown.send_keys("user-#{$random_seed}-exp")
    @wait.until {wait_for_plotly_render('#cluster-plot', 'rendered')}

    # make sure the new annotation still renders a plot for plotly
    annot_rendered = @driver.execute_script("return $('#cluster-plot').data('rendered')")
    assert annot_rendered, "cluster plot did not finish rendering on annotation change, expected true but found #{annot_rendered}"

    # load random gene to search
    gene = @genes.sample
    search_box = @driver.find_element(:id, 'search_genes')
    search_box.send_keys(gene)
    wait_for_render(:id, 'perform-gene-search')
    search_genes = @driver.find_element(:id, 'perform-gene-search')
    search_genes.click

    # make sure the new annotation still renders plots for plotly
    assert element_present?(:id, 'box-controls'), 'could not find expression violin plot'
    assert element_present?(:id, 'scatter-plots'), 'could not find expression scatter plots'

    # confirm queried gene is the one returned
    queried_gene = @driver.find_element(:class, 'queried-gene')
    assert queried_gene.text == gene, "did not load the correct gene, expected #{gene} but found #{queried_gene.text}"

    # wait until violin plot renders, at this point all 3 should be done
    @wait.until {wait_for_plotly_render('#expression-plots', 'box-rendered')}
    violin_rendered = @driver.execute_script("return $('#expression-plots').data('box-rendered')")
    assert violin_rendered, "violin plot did not finish rendering, expected true but found #{violin_rendered}"
    scatter_rendered = @driver.execute_script("return $('#expression-plots').data('scatter-rendered')")
    assert scatter_rendered, "scatter plot did not finish rendering, expected true but found #{scatter_rendered}"
    reference_rendered = @driver.execute_script("return $('#expression-plots').data('reference-rendered')")
    assert reference_rendered, "reference plot did not finish rendering, expected true but found #{reference_rendered}"

    # change to box plot
    plot_dropdown = @driver.find_element(:id, 'plot_type')
    plot_ops = plot_dropdown.find_elements(:tag_name, 'option')
    new_plot = plot_ops.select {|opt| !opt.selected?}.sample.text
    plot_dropdown.send_keys(new_plot)

    # wait until box plot renders, at this point all 3 should be done
    @wait.until {wait_for_plotly_render('#expression-plots', 'box-rendered')}
    box_rendered = @driver.execute_script("return $('#expression-plots').data('box-rendered')")
    assert box_rendered, "box plot did not finish rendering, expected true but found #{box_rendered}"
    scatter_rendered = @driver.execute_script("return $('#expression-plots').data('scatter-rendered')")
    assert scatter_rendered, "scatter plot did not finish rendering, expected true but found #{scatter_rendered}"
    reference_rendered = @driver.execute_script("return $('#expression-plots').data('reference-rendered')")
    assert reference_rendered, "reference plot did not finish rendering, expected true but found #{reference_rendered}"

    search_menu = @driver.find_element(:id, 'search-omnibar-menu-icon')
    search_menu.click
    wait_for_render(:id, 'search_consensus')
    gene_list_panel = @driver.find_element(:id, 'gene-lists-link')
    gene_list_panel.click
    wait_for_render(:id, 'expression')
    sleep(1)
    gene_sets = @driver.find_element(:id, 'gene_set')
    opts = gene_sets.find_elements(:tag_name, 'option').delete_if {|o| o.text == 'Please select a gene list'}
    list = opts.last
    gene_list_name = list['value']
    gene_sets.send_keys(gene_list_name)

    # wait until violin plot renders, at this point all 3 should be done
    @wait.until {wait_for_plotly_render('#expression-plots', 'box-rendered')}
    violin_rendered = @driver.execute_script("return $('#expression-plots').data('box-rendered')")
    assert violin_rendered, "violin plot did not finish rendering, expected true but found #{violin_rendered}"
    scatter_rendered = @driver.execute_script("return $('#expression-plots').data('scatter-rendered')")
    assert scatter_rendered, "scatter plot did not finish rendering, expected true but found #{scatter_rendered}"
    reference_rendered = @driver.execute_script("return $('#expression-plots').data('reference-rendered')")
    assert reference_rendered, "reference plot did not finish rendering, expected true but found #{reference_rendered}"

    puts "#{File.basename(__FILE__)}: '#{self.method_name}' successful!"
  end

  # make sure editing the annotation works
  test 'front-end: user-annotation: editing' do
    puts "#{File.basename(__FILE__)}: '#{self.method_name}'"

    # login
    @driver.get @base_url
    login($test_email, $test_email_password)

    # load annotation panel
    annot_path = @base_url + '/user_annotations'
    @driver.get annot_path

    @driver.find_element(:class, "user-#{$random_seed}-edit").click
    wait_for_render(:id, 'user_annotation_name')

    # add 'new' to the name of annotation
    name = @driver.find_element(:id, 'user_annotation_name')
    name.send_keys("new")

    # add 'new' to the labels
    annotation_labels = @driver.find_elements(:id, 'user-annotation_values')

    annotation_labels.each_with_index do |annot, i|
      annot.clear
      annot.send_keys("group#{i}new")
    end

    # update the annotation
    submit = @driver.find_element(:id, 'submit-button')
    submit.click

    wait_for_render(:class, 'annotation-name')

    # check names and labels
    new_names = @driver.find_elements(:class, 'annotation-name').map{|x| x.text }
    new_labels = @driver.find_elements(:class, "user-#{$random_seed}new").map{|x| x.text }

    # assert new name saved correctly
    assert (new_names.include? "user-#{$random_seed}new"), "Name edit failed, expected 'user-#{$random_seed}new' but got '#{new_names}'"

    # assert labels saved correctly
    assert (new_labels.include? "group0new"), "Name edit failed, expected 'new in group' but got '#{new_labels}'"
    close_modal('message_modal')

    # View the annotation
    @driver.find_element(:class, "user-#{$random_seed}new-show").click

    # assert the plot still renders
    @wait.until {wait_for_plotly_render('#cluster-plot', 'rendered')}
    annot_rendered = @driver.execute_script("return $('#cluster-plot').data('rendered')")
    assert annot_rendered, "cluster plot did not finish rendering on annotation change, expected true but found #{annot_rendered}"

    # assert labels are correct
    plot_labels = @driver.find_elements(:class, "legendtext").map(&:text)
    assert plot_labels.grep(/user-#{$random_seed}new:.group0new/).any?, "labels are incorrect: '#{plot_labels}' should include 'user-#{$random_seed}new: group0new'"

    # revert the annotation to old name and labels
    @driver.get annot_path
    @driver.find_element(:class, "user-#{$random_seed}new-edit").click
    wait_for_render(:id, 'user_annotation_name')

    # revert name
    name = @driver.find_element(:id, 'user_annotation_name')
    name.clear
    name.send_keys("user-#{$random_seed}")

    # revert labels
    annotation_labels = @driver.find_elements(:id, 'user-annotation_values')

    annotation_labels.each_with_index do |annot, i|
      annot.clear
      annot.send_keys("group#{i}")
    end

    # update annotation
    submit = @driver.find_element(:id, 'submit-button')
    submit.click

    wait_for_render(:class, 'annotation-name')


    # check new names and labels
    new_names = @driver.find_elements(:class, 'annotation-name').map{|x| x.text }
    new_labels = @driver.find_elements(:class, "user-#{$random_seed}").map{|x| x.text }

    # assert new name saved correctly
    assert !(new_names.include? "user-#{$random_seed}new"), "Name edit failed, expected 'user-#{$random_seed}' but got '#{new_names}'"

    # assert labels saved correctly
    assert !(new_labels.include? "group0new"), "Name edit failed, did not expect 'new in group' but got '#{new_labels}'"

    close_modal('message_modal')

    # View the annotation
    @driver.find_element(:class, "user-#{$random_seed}-show").click

    # assert the plot still renders
    @wait.until {wait_for_plotly_render('#cluster-plot', 'rendered')}
    annot_rendered = @driver.execute_script("return $('#cluster-plot').data('rendered')")
    assert annot_rendered, "cluster plot did not finish rendering on annotation change, expected true but found #{annot_rendered}"

    # assert labels are correct
    plot_labels = @driver.find_elements(:class, "legendtext").map(&:text)
    assert plot_labels.grep(/user-#{$random_seed}:.group0/).any?, "labels are incorrect: '#{plot_labels}' should include 'user-#{$random_seed}: group0'"

    puts "#{File.basename(__FILE__)}: '#{self.method_name}' successful!"
  end

  # make sure sharing the annotation works
  test 'front-end: user-annotation: sharing' do
    puts "#{File.basename(__FILE__)}: '#{self.method_name}'"

    # login
    @driver.get @base_url
    login($test_email, $test_email_password)

    # load annotation panel
    annot_path = @base_url + '/user_annotations'
    @driver.get annot_path

    @driver.find_element(:class, "user-#{$random_seed}-exp-edit").click
    wait_for_render(:id, 'add-user-annotation-share')
    # click the share button
    share_button = @driver.find_element(:id, 'add-user-annotation-share')
    share_button.click

    share_email = @driver.find_element(:class, 'share-email')
    share_email.send_keys($share_email)

    share_permission = @driver.find_element(:class, 'share-permission')
    share_permission.send_keys('Edit')

    # update the annotation
    submit = @driver.find_element(:id, 'submit-button')
    submit.click
    close_modal('message_modal')

    # logout
    logout_from_portal

    # login
    login_as_other($test_email, $test_email_password)
    # load annotation panel
    annot_path = @base_url + '/user_annotations'
    @driver.get annot_path

    # View the annotation
    wait_until_page_loads(annot_path)
    @driver.find_element(:class, "user-#{$random_seed}-exp-show").click

    # make sure the new annotation still renders a plot for plotly
    @wait.until {wait_for_plotly_render('#cluster-plot', 'rendered')}
    annot_rendered = @driver.execute_script("return $('#cluster-plot').data('rendered')")
    assert annot_rendered, "cluster plot did not finish rendering on annotation change, expected true but found #{annot_rendered}"

    # load random gene to search
    gene = @genes.sample
    search_box = @driver.find_element(:id, 'search_genes')
    search_box.send_keys(gene)
    wait_for_render(:id, 'perform-gene-search')
    search_genes = @driver.find_element(:id, 'perform-gene-search')
    search_genes.click

    # make sure the new annotation still renders plots for plotly
    assert element_present?(:id, 'box-controls'), 'could not find expression violin plot'
    assert element_present?(:id, 'scatter-plots'), 'could not find expression scatter plots'

    wait_for_render(:class, 'queried-gene')
    # confirm queried gene is the one returned
    queried_gene = @driver.find_element(:class, 'queried-gene')
    assert queried_gene.text == gene, "did not load the correct gene, expected #{gene} but found #{queried_gene.text}"

    # wait until violin plot renders, at this point all 3 should be done
    @wait.until {wait_for_plotly_render('#expression-plots', 'box-rendered')}
    violin_rendered = @driver.execute_script("return $('#expression-plots').data('box-rendered')")
    assert violin_rendered, "violin plot did not finish rendering, expected true but found #{violin_rendered}"
    scatter_rendered = @driver.execute_script("return $('#expression-plots').data('scatter-rendered')")
    assert scatter_rendered, "scatter plot did not finish rendering, expected true but found #{scatter_rendered}"
    reference_rendered = @driver.execute_script("return $('#expression-plots').data('reference-rendered')")
    assert reference_rendered, "reference plot did not finish rendering, expected true but found #{reference_rendered}"

    # change to box plot
    view_options_panel = @driver.find_element(:id, 'view-option-link')
    view_options_panel.click
    wait_for_render(:id, 'view-options')
    plot_dropdown = @driver.find_element(:id, 'plot_type')
    plot_ops = plot_dropdown.find_elements(:tag_name, 'option')
    new_plot = plot_ops.select {|opt| !opt.selected?}.sample.text
    plot_dropdown.send_keys(new_plot)

    # wait until box plot renders, at this point all 3 should be done
    @wait.until {wait_for_plotly_render('#expression-plots', 'box-rendered')}
    box_rendered = @driver.execute_script("return $('#expression-plots').data('box-rendered')")
    assert box_rendered, "box plot did not finish rendering, expected true but found #{box_rendered}"
    scatter_rendered = @driver.execute_script("return $('#expression-plots').data('scatter-rendered')")
    assert scatter_rendered, "scatter plot did not finish rendering, expected true but found #{scatter_rendered}"
    reference_rendered = @driver.execute_script("return $('#expression-plots').data('reference-rendered')")
    assert reference_rendered, "reference plot did not finish rendering, expected true but found #{reference_rendered}"

    sleep 0.5

    search_menu = @driver.find_element(:id, 'search-omnibar-menu-icon')
    search_menu.click
    wait_for_render(:id, 'search_consensus')
    gene_list_panel = @driver.find_element(:id, 'gene-lists-link')
    gene_list_panel.click
    wait_for_render(:id, 'expression')
    sleep(1)
    gene_sets = @driver.find_element(:id, 'gene_set')
    opts = gene_sets.find_elements(:tag_name, 'option').delete_if {|o| o.text == 'Please select a gene list'}
    list = opts.last
    gene_list_name = list['value']
    gene_sets.send_keys(gene_list_name)

    # wait until violin plot renders, at this point all 3 should be done
    @wait.until {wait_for_plotly_render('#expression-plots', 'box-rendered')}
    violin_rendered = @driver.execute_script("return $('#expression-plots').data('box-rendered')")
    assert violin_rendered, "violin plot did not finish rendering, expected true but found #{violin_rendered}"
    scatter_rendered = @driver.execute_script("return $('#expression-plots').data('scatter-rendered')")
    assert scatter_rendered, "scatter plot did not finish rendering, expected true but found #{scatter_rendered}"
    reference_rendered = @driver.execute_script("return $('#expression-plots').data('reference-rendered')")
    assert reference_rendered, "reference plot did not finish rendering, expected true but found #{reference_rendered}"

    # revert the annotation to old name and labels
    @driver.get annot_path
    @driver.find_element(:class, "user-#{$random_seed}-exp-edit").click
    wait_for_render(:id, 'user_annotation_name')

    # change name
    name = @driver.find_element(:id, 'user_annotation_name')
    name.clear
    name.send_keys("user-#{$random_seed}-exp-Share")

    # update annotation
    submit = @driver.find_element(:id, 'submit-button')
    submit.click

    wait_until_page_loads(annot_path)

    # check new names and labels
    new_names = @driver.find_elements(:class, 'annotation-name').map{|x| x.text }

    # assert new name saved correctly
    assert (new_names.include? "user-#{$random_seed}-exp-Share"), "Name edit failed, expected 'user-#{$random_seed}-exp-Share' but got '#{new_names}'"
    close_modal('message_modal')

    # View the annotation
    @driver.find_element(:class, "user-#{$random_seed}-exp-share-show").click

    # assert the plot still renders
    @wait.until {wait_for_plotly_render('#cluster-plot', 'rendered')}
    annot_rendered = @driver.execute_script("return $('#cluster-plot').data('rendered')")
    assert annot_rendered, "cluster plot did not finish rendering on annotation change, expected true but found #{annot_rendered}"

    # assert labels are correct
    plot_labels = @driver.find_elements(:class, "legendtext").map(&:text)
    assert plot_labels.grep(/user-#{$random_seed}-exp-Share:.group0/).any?, "labels are incorrect: '#{plot_labels}' should include 'user-#{$random_seed}-exp-Share: group0'"

    # logout
    logout_from_portal

    # login
    login_as_other($test_email, $test_email_password)

    # load annotation panel
    annot_path = @base_url + '/user_annotations'
    @driver.get annot_path

    @driver.find_element(:class, "user-#{$random_seed}-exp-share-edit").click
    wait_for_render(:id, 'add-user-annotation-share')

    # click the share button
    share_button = @driver.find_element(:id, 'add-user-annotation-share')
    share_button.click

    share_email = @driver.find_element(:class, 'share-email')
    share_email.send_keys($share_email)

    share_permission = @driver.find_element(:class, 'share-permission')
    share_permission.send_keys('View')

    # change name
    name = @driver.find_element(:id, 'user_annotation_name')
    name.clear
    name.send_keys("user-#{$random_seed}-exp")

    # update the annotation
    submit = @driver.find_element(:id, 'submit-button')
    submit.click
    wait_until_page_loads(annot_path)
    close_modal('message_modal')

    # logout
    logout_from_portal

    # login
    login_as_other($share_email, $share_email_password)

    # load annotation panel
    annot_path = @base_url + '/user_annotations'
    @driver.get annot_path

    # make sure can't edit
    editable = element_present?(:class, "user-#{$random_seed}-exp-edit")
    assert !editable, 'Edit button found'

    # View the annotation
    @driver.find_element(:class, "user-#{$random_seed}-exp-show").click

    # assert the plot still renders
    @wait.until {wait_for_plotly_render('#cluster-plot', 'rendered')}
    annot_rendered = @driver.execute_script("return $('#cluster-plot').data('rendered')")
    assert annot_rendered, "cluster plot did not finish rendering on annotation change, expected true but found #{annot_rendered}"

    puts "#{File.basename(__FILE__)}: '#{self.method_name}' successful!"
  end

  test 'front-end: user-annotation: download annotation cluster file' do
    puts "#{File.basename(__FILE__)}: '#{self.method_name}'"
    @driver.get @base_url
    login($test_email, $test_email_password)

    # load annotation panel
    annot_path = @base_url + '/user_annotations'
    @driver.get annot_path

    # Click download and get filenames
    filename = (@driver.find_element(:class, "user-#{$random_seed}_cluster").attribute('innerHTML') + "_user-#{$random_seed}.txt").gsub(/ /, '_')
    basename = filename.split('.').first

    @driver.find_element(:class, "user-#{$random_seed}-download").click
    # give browser 5 seconds to initiate download
    sleep(5)
    # make sure file was actually downloaded
    file_exists = Dir.entries($download_dir).select {|f| f =~ /#{basename}/}.size >= 1 || File.exists?(File.join($download_dir, filename))
    assert file_exists, "did not find downloaded file: #{filename} in #{Dir.entries($download_dir).join(', ')}"

    # delete matching files
    Dir.glob("#{$download_dir}/*").select {|f| /#{basename}/.match(f)}.map {|f| File.delete(f)}

    puts "#{File.basename(__FILE__)}: '#{self.method_name}' successful!"
  end

  # check user annotation publishing
  test 'front-end: user-annotation: publishing' do
    puts "#{File.basename(__FILE__)}: '#{self.method_name}'"

    # login
    @driver.get @base_url
    login($test_email, $test_email_password)

    # load annotation panel
    annot_path = @base_url + '/user_annotations'
    @driver.get annot_path

    num_annotations = @driver.find_elements(:class, 'annotation-name').length

    @driver.find_element(:class, "user-#{$random_seed}-publish").click
    accept_alert
    close_modal('message_modal')

    new_num_annotations = num_annotations
    i = 0
    while new_num_annotations >= num_annotations
      if i == 5
        assert false, "Reloaded the page five times but found #{new_num_annotations} rows instead of #{num_annotations-1} rows, indicating that the annotation was not deleted."
      end
      sleep 1.0
      @driver.get annot_path
      new_num_annotations = @driver.find_elements(:class, 'annotation-name').length
      i+=1
    end

    # check new names
    new_names = @driver.find_elements(:class, 'annotation-name').map{|x| x.text }

    # assert new name saved correctly
    assert !(new_names.include? "user-#{$random_seed}"), "Persist failed, expected no 'user-#{$random_seed}' but found it"

    # Wait for the annotation to persist
    sleep 3.0

    # go to study and make sure this annotation is saved
    two_d_study_path = @base_url + "/study/twod-study-#{$random_seed}"
    @driver.get two_d_study_path
    study_accession = extract_accession_from_url(@driver.current_url)
    loaded_2d_path = @base_url + "/study/#{study_accession}/twod-study-#{$random_seed}"
    wait_until_page_loads(loaded_2d_path)
    open_ui_tab('study-visualize')

    # choose the newly persisted annotation
    @wait.until {wait_for_plotly_render('#cluster-plot', 'rendered')}
    view_options_panel = @driver.find_element(:id, 'view-option-link')
    view_options_panel.click
    wait_for_render(:id, 'view-options')
    annotation_dropdown = @driver.find_element(:id, 'annotation')
    annotation_dropdown.send_keys("user-#{$random_seed}")
    @wait.until {wait_for_plotly_render('#cluster-plot', 'rendered')}

    # make sure the new annotation still renders a plot for plotly
    annot_rendered = @driver.execute_script("return $('#cluster-plot').data('rendered')")
    assert annot_rendered, "cluster plot did not finish rendering on annotation change, expected true but found #{annot_rendered}"

    # load random gene to search
    gene = @genes.sample
    search_box = @driver.find_element(:id, 'search_genes')
    search_box.send_keys(gene)
    search_genes = @driver.find_element(:id, 'perform-gene-search')
    search_genes.click

    # make sure the new annotation still renders plots for plotly
    assert element_present?(:id, 'box-controls'), 'could not find expression violin plot'
    assert element_present?(:id, 'scatter-plots'), 'could not find expression scatter plots'

    # confirm queried gene is the one returned
    queried_gene = @driver.find_element(:class, 'queried-gene')
    assert queried_gene.text == gene, "did not load the correct gene, expected #{gene} but found #{queried_gene.text}"

    # wait until violin plot renders, at this point all 3 should be done
    @wait.until {wait_for_plotly_render('#expression-plots', 'box-rendered')}
    violin_rendered = @driver.execute_script("return $('#expression-plots').data('box-rendered')")
    assert violin_rendered, "violin plot did not finish rendering, expected true but found #{violin_rendered}"
    scatter_rendered = @driver.execute_script("return $('#expression-plots').data('scatter-rendered')")
    assert scatter_rendered, "scatter plot did not finish rendering, expected true but found #{scatter_rendered}"
    reference_rendered = @driver.execute_script("return $('#expression-plots').data('reference-rendered')")
    assert reference_rendered, "reference plot did not finish rendering, expected true but found #{reference_rendered}"

    # change to box plot
    plot_dropdown = @driver.find_element(:id, 'plot_type')
    plot_ops = plot_dropdown.find_elements(:tag_name, 'option')
    new_plot = plot_ops.select {|opt| !opt.selected?}.sample.text
    plot_dropdown.send_keys(new_plot)

    # wait until box plot renders, at this point all 3 should be done
    @wait.until {wait_for_plotly_render('#expression-plots', 'box-rendered')}
    box_rendered = @driver.execute_script("return $('#expression-plots').data('box-rendered')")
    assert box_rendered, "box plot did not finish rendering, expected true but found #{box_rendered}"
    scatter_rendered = @driver.execute_script("return $('#expression-plots').data('scatter-rendered')")
    assert scatter_rendered, "scatter plot did not finish rendering, expected true but found #{scatter_rendered}"
    reference_rendered = @driver.execute_script("return $('#expression-plots').data('reference-rendered')")
    assert reference_rendered, "reference plot did not finish rendering, expected true but found #{reference_rendered}"

    search_menu = @driver.find_element(:id, 'search-omnibar-menu-icon')
    search_menu.click
    wait_for_render(:id, 'search_consensus')
    gene_list_panel = @driver.find_element(:id, 'gene-lists-link')
    gene_list_panel.click
    wait_for_render(:id, 'expression')
    sleep(1)
    gene_sets = @driver.find_element(:id, 'gene_set')
    opts = gene_sets.find_elements(:tag_name, 'option').delete_if {|o| o.text == 'Please select a gene list'}
    list = opts.sample['value']
    @driver.execute_script("$('expression-plots').data('box-rendered', false);")
    gene_sets.send_keys(list)
    assert element_present?(:id, 'expression-plots'), 'could not find box/scatter divs'
    sleep(1)

    # wait until violin plot renders, at this point all 3 should be done
    @wait.until {wait_for_plotly_render('#expression-plots', 'box-rendered')}
    violin_rendered = @driver.execute_script("return $('#expression-plots').data('box-rendered')")
    assert violin_rendered, "violin plot did not finish rendering, expected true but found #{violin_rendered}"
    scatter_rendered = @driver.execute_script("return $('#expression-plots').data('scatter-rendered')")
    assert scatter_rendered, "scatter plot did not finish rendering, expected true but found #{scatter_rendered}"
    reference_rendered = @driver.execute_script("return $('#expression-plots').data('reference-rendered')")
    assert reference_rendered, "reference plot did not finish rendering, expected true but found #{reference_rendered}"

    scroll_to(:top)
    open_ui_tab('study-download')

    download_button = @driver.find_element(:class, 'cluster-file')
    download_button.click

    # get the file contents
    contents = @driver.find_element(:tag_name, 'pre').text
    first_line = contents.split("\n").first.split.map(&:strip)
    %w[NAME X Y Sub-Group].each do |header|
      assert first_line.include?(header), "Original cluster's rows are absent, rows: #{first_line}, is missing #{header}"
    end
    assert (first_line.include?("user-#{$random_seed}")), "New annotation's rows are absent, rows: #{first_line}, missing: user-#{$random_seed}"

    puts "#{File.basename(__FILE__)}: '#{self.method_name}' successful!"
  end

  # check user annotation deletion
  test 'front-end: user-annotation: deletion' do
    puts "#{File.basename(__FILE__)}: '#{self.method_name}'"

    # login
    @driver.get @base_url
    login($test_email, $test_email_password)

    # load annotation panel
    annot_path = @base_url + '/user_annotations'
    @driver.get annot_path

    delete_btn = @driver.find_element(:class, "user-#{$random_seed}-exp-delete")
    delete_btn.click
    accept_alert
    close_modal('message_modal')

    #check new names
    first_row = @driver.find_element(:id, 'annotations').find_element(:tag_name, 'tbody').find_element(:tag_name, 'tr').find_element(:tag_name, 'td')
    unless first_row['class'] == 'dataTables_empty'
      #If you dont't have any annotations, they were all deleted
      new_names = @driver.find_elements(:class, 'annotation-name').map{|x| x.text }
      #assert new name saved correctly
      assert !(new_names.include? "user-#{$random_seed}-exp"), "Deletion failed, expected no 'user-#{$random_seed}-exp' but found it"
    end

    puts "#{File.basename(__FILE__)}: '#{self.method_name}' successful!"
  end

  ##
  ## WORKFLOW TESTS
  ## Test FireCloud workflow integration with analysis configurations & submission/syncing outputs


  # test creating & cancelling submissions of workflows
  test 'front-end: workflows: launch and cancel submissions' do
    puts "#{File.basename(__FILE__)}: '#{self.method_name}'"

    @driver.get @base_url
    login($test_email, $test_email_password)

    study_page = @base_url + "/study/test-study-#{$random_seed}"
    @driver.get study_page
    study_accession = extract_accession_from_url(@driver.current_url)
    loaded_path = @base_url + "/study/#{study_accession}/test-study-#{$random_seed}"
    wait_until_page_loads(loaded_path)

    # select worfklow & sample
    open_ui_tab('study-analysis')
    wait_for_render(:id, 'workflow_identifier')
    scroll_to(:bottom)
    wdl_workdropdown = @driver.find_element(:id, 'workflow_identifier')
    wdl_workflows = wdl_workdropdown.find_elements(:tag_name, 'option')
    workflow = wdl_workflows.detect {|w| w['value'] == 'single-cell-portal--split-cluster--1'}
    wdl_workdropdown.send_keys(workflow['value'])
    # view WDL to allow time for sample input browser to render fully
    view_wdl = @driver.find_element(:id, 'view-selected-wdl')
    view_wdl.click
    wait_for_render(:id, 'wdl-contents')
    wdl_contents = @driver.find_element(:id, 'wdl-contents').text
    assert !wdl_contents.empty?, 'Did not find any contents for test WDL'


    # submit workflow
    configure_nav = @driver.find_element(:id, 'select-inputs-nav')
    configure_nav.click
    wait_for_render(:id, 'submit-workflow')
    workflow_form = @driver.find_element(:id, 'workflow-submission')
    # check doc links
    doc_link = workflow_form.find_element(:class, 'external-resource-link')
    assert !doc_link.nil?, 'Did not find documentation link'
    expected_doc_link = 'https://portal.firecloud.org/#methods/single-cell-portal/split-cluster/1'
    assert doc_link['href'] == expected_doc_link,
           "Documentation link is incorrect, expected '#{expected_doc_link}' but found '#{doc_link['href']}'"
    submit_btn = @driver.find_element(id: 'submit-workflow')
    submit_btn.click
    close_modal('generic-update-modal')

    # abort workflow
    scroll_to(:top)
    abort_btn = @driver.find_element(:class, 'abort-submission')
    abort_btn.click
    accept_alert
    wait_for_modal_open('generic-update-modal')
    expected_conf = 'Submission Successfully Cancelled'
    confirmation = @driver.find_element(:id, 'generic-update-modal-title').text
    assert confirmation == expected_conf, "Did not find correct confirmation message, expected '#{expected_conf}' but found '#{confirmation}'"
    close_modal('generic-update-modal')

    # submit new workflow
    submit_btn = @driver.find_element(id: 'submit-workflow')
    submit_btn.click
    close_modal('generic-update-modal')

    # force a refresh of the table
    scroll_to(:top)
    refresh_btn = @driver.find_element(:id, 'refresh-submissions-table-top')
    refresh_btn.click
    sleep(3)

    # assert there are two workflows, one aborted and one submitted
    submissions_table = @driver.find_element(:id, 'submissions-table')
    submissions = submissions_table.find_element(:tag_name, 'tbody').find_elements(:tag_name, 'tr')
    assert submissions.size >= 2, "Did not find correct number of submissions, expected at least 2 but found #{submissions.size}"
    submissions.each do |submission|
      submission_id = submission['id']
      submission_state = @driver.find_element(:id, "submission-#{submission_id}-state").text
      submission_status = @driver.find_element(:id, "submission-#{submission_id}-status").text
      if %w(Aborting Aborted).include?(submission_state)
        assert %w(Queued Submitted Failed Aborting Aborted).include?(submission_status), "Found incorrect submissions status for aborted submission #{submission_id}: #{submission_status}"
      else
        assert %w(Queued Submitted Launching Running Succeeded).include?(submission_status), "Found incorrect submissions status for regular submission #{submission_id}: #{submission_status}"
      end
    end
    puts "#{File.basename(__FILE__)}: '#{self.method_name}' successful!"
  end

  # test syncing outputs from submission
  test 'front-end: workflows: sync outputs' do
    puts "#{File.basename(__FILE__)}: '#{self.method_name}'"

    @driver.get @base_url
    login($test_email, $test_email_password)

    study_page = @base_url + "/study/test-study-#{$random_seed}"
    @driver.get study_page
    study_accession = extract_accession_from_url(@driver.current_url)
    loaded_path = @base_url + "/study/#{study_accession}/test-study-#{$random_seed}"
    wait_until_page_loads(loaded_path)
    open_ui_tab('study-analysis')
    wait_for_render(:id, 'submissions-table')

    # make sure submission has completed
    submissions_table = @driver.find_element(:id, 'submissions-table')
    submissions = submissions_table.find_element(:tag_name, 'tbody').find_elements(:tag_name, 'tr')
    completed_submission = submissions.find {|sub|
      sub.find_element(:class, "submission-state").text == 'Done' &&
          sub.find_element(:class, "submission-status").text == 'Succeeded'
    }
    i = 1
    while completed_submission.nil?
      omit_if i >= 120, 'Skipping test; waited 10 minutes but no submissions complete yet.'

      $verbose ? puts("no completed submissions, refresh try ##{i}") : nil
      refresh_btn = @driver.find_element(:id, 'refresh-submissions-table-top')
      refresh_btn.click
      sleep 5
      submissions_table = @driver.find_element(:id, 'submissions-table')
      submissions = submissions_table.find_element(:tag_name, 'tbody').find_elements(:tag_name, 'tr')
      completed_submission = submissions.find {|sub|
        sub.find_element(:class, "submission-state").text == 'Done' &&
            sub.find_element(:class, "submission-status").text == 'Succeeded'
      }
      i += 1
    end

    # sync an output file
    sync_btn = completed_submission.find_element(:class, 'sync-submission-outputs')
    sync_btn.click
    wait_for_render(:class, 'unsynced-study-file')
    study_file_forms = @driver.find_elements(:class, 'unsynced-study-file')
    study_file_forms.each_with_index do |form, index|
      file_type = form.find_element(:id, 'study_file_file_type')
      selected_type = file_type.find_elements(:tag_name, 'option').detect {|opt| opt.selected?}.text
      assert selected_type == 'Cluster', "Did not set file type correctly, expected 'Cluster' but found '#{selected_type}'"
      description = form.find_element(:id, 'study_file_description')
      expected_description = "Description set from run #{$random_seed}"
      assert description['value'] == expected_description,
             "Did not set description correctly, expected '#{expected_description}' but found '#{description['value']}'"
      cluster_name_field = form.find_element(:id, 'study_file_name')
      cluster_name_field.clear
      cluster_name_field.send_keys("Split Cluster #{index + 1}")
      sync_button = form.find_element(:class, 'save-study-file')
      sync_button.click
      close_modal('sync-notice-modal')
    end
    scroll_to(:bottom)
    synced_toggle = @driver.find_element(:id, 'synced-data-panel-toggle')
    synced_toggle.click
    wait_for_render(:class, 'synced-study-file')
    synced_files = @driver.find_elements(:class, 'synced-study-file')
    filenames = synced_files.map {|form| form.find_element(:class, 'filename')[:value]}
    assert filenames.any?, "Did not find any files in list of synced files: #{filenames.join(', ')}"
    # assert new clusters have been added
    # sleep 15 seconds to give portal a chance to parse files
    sleep(15)
    @driver.get loaded_path
    wait_until_page_loads(loaded_path)
    open_ui_tab('study-visualize')
    wait_for_render(:id, 'plots-tab')
    @wait.until {wait_for_plotly_render('#cluster-plot', 'rendered')}

    # assert all new clusters are present
    view_options_panel = @driver.find_element(:id, 'view-option-link')
    view_options_panel.click
    wait_for_render(:id, 'view-options')
    clusters = @driver.find_element(:id, 'cluster').find_elements(:tag_name, 'option')
    names = clusters.map {|cluster| cluster.text}
    expected_names = ['Split Cluster 1', 'Split Cluster 2']
    assert expected_names & names == expected_names, "Did not find expected names of '#{expected_names}' in '#{names}'"

    puts "#{File.basename(__FILE__)}: '#{self.method_name}' successful!"
  end

  # view/export metadata from a submission
  test 'front-end: workflows: export metadata' do
    puts "#{File.basename(__FILE__)}: '#{self.method_name}'"

    @driver.get @base_url
    login($test_email, $test_email_password)

    study_page = @base_url + "/study/test-study-#{$random_seed}"
    @driver.get study_page
    study_accession = extract_accession_from_url(@driver.current_url)
    loaded_path = @base_url + "/study/#{study_accession}/test-study-#{$random_seed}"
    wait_until_page_loads(loaded_path)
    open_ui_tab('study-analysis')
    wait_for_render(:id, 'submissions-table')

    # find a completed submission
    submissions_table = @driver.find_element(:id, 'submissions-table')
    submissions = submissions_table.find_element(:tag_name, 'tbody').find_elements(:tag_name, 'tr')
    completed_submission = submissions.find {|sub|
      sub.find_element(:class, "submission-state").text == 'Done' &&
          sub.find_element(:class, "submission-status").text == 'Succeeded'
    }

    omit_if completed_submission.nil?, 'Skipping test; No completed submissions'

    # view run metadata
    view_btn = completed_submission.find_element(:class, 'view-submission-metadata')
    view_btn.click
    wait_for_modal_open('generic-update-modal')

    # export analysis.json file
    export_btn = @driver.find_element(:class, 'export-submission-metadata')
    export_btn.click
    sleep(1)
    filename = 'analysis.json'
    filepath = File.join($download_dir, filename)
    assert File.exist?(filepath), "Did not find exported analysis metadata at #{filepath}"

    # make sure exported file is valid by checking for some expected keys
    analysis_file = File.open(filepath)
    analysis_json = JSON.parse(analysis_file.read)
    assert %w(inputs outputs name tasks analysis_id).all? {|k| analysis_json.has_key?(k)}, "Exported analysis file does not have required keys: #{analysis_json.keys}"

    # clean up
    File.delete(filepath)

    puts "#{File.basename(__FILE__)}: '#{self.method_name}' successful!"
  end

  # delete submissions from study, and remove the analysis configuration
  test 'front-end: workflows: delete submissions and analysis configuration' do
    puts "#{File.basename(__FILE__)}: '#{self.method_name}'"

    @driver.get @base_url
    login($test_email, $test_email_password)

    study_page = @base_url + "/study/test-study-#{$random_seed}"
    @driver.get study_page
    study_accession = extract_accession_from_url(@driver.current_url)
    loaded_path = @base_url + "/study/#{study_accession}/test-study-#{$random_seed}"
    wait_until_page_loads(loaded_path)
    open_ui_tab('study-analysis')
    wait_for_render(:id, 'submissions-table')
    submissions_table = @driver.find_element(:id, 'submissions-table')
    submission_ids = submissions_table.find_element(:tag_name, 'tbody').find_elements(:tag_name, 'tr').map {|s| s['id']}.delete_if {|id| id.empty?}
    submission_ids.each do |submission_id|
      submission = @driver.find_element(:id, submission_id)
      delete_btn = submission.find_element(:class, 'delete-submission-files')
      delete_btn.click
      accept_alert
      close_modal('generic-update-modal')
      # let table refresh complete
      sleep(3)
    end
    empty_table = @driver.find_element(:id, 'submissions-table')
    empty_row = empty_table.find_element(:tag_name, 'tbody').find_element(:tag_name, 'tr').find_element(:tag_name, 'td')
    assert empty_row.text == 'No data available in table', "Did not completely remove all submissions, expected 'No data available in table' but found #{empty_row.text}"

    # remove analysis configuration
    analysis_config_path = @base_url + '/analysis_configurations'
    @driver.get analysis_config_path
    wait_until_page_loads(analysis_config_path)
    delete_btn = @driver.find_element(:class, 'single-cell-portal-split-cluster-1-delete')
    delete_btn.click
    accept_alert

    puts "#{File.basename(__FILE__)}: '#{self.method_name}' successful!"
  end

  # Test loading data from GCS into Ideogram; also tests the ability to view a study w/o clusters, metadata, or
  # gene expression.  Relies on a FireCloud workspace called development-ideogram-only
  test 'front-end: ideogram only' do
    puts "#{File.basename(__FILE__)}: '#{self.method_name}'"

    # log in first
    @driver.get @base_url
    login($test_email, $test_email_password)
    @driver.get @base_url + '/studies/new'

    random_name = "Ideogram Only #{$random_seed}"
    study_form = @driver.find_element(:id, 'new_study')
    study_form.find_element(:id, 'study_name').send_keys(random_name)
    study_form.find_element(:id, 'study_use_existing_workspace').send_keys('Yes')
    study_form.find_element(:id, 'study_firecloud_workspace').send_keys("development-ideogram-only")
    # Note that we're not sharing this with "share_email", to enable a later part of this test

    # save study
    save_study = @driver.find_element(:id, 'save-study')
    save_study.click
    @wait.until {element_present?(:id, 'unsynced-study-files')}
    close_modal('message_modal')

    study_file_forms = @driver.find_elements(:class, 'unsynced-study-file')
    study_file_forms.each do |form|
      file_type = form.find_element(:id, 'study_file_file_type')
      file_type.send_keys('Ideogram Annotations')
      species_dropdown = form.find_element(:id, 'study_file_taxon_id')
      @wait.until {file_type.displayed?}
      species_dropdown.send_keys('human') # from lib/assets/default_species_assemblies.txt
      sleep(2) # this is required as the assemblies dropdown is about to get re-rendered, so we don't want a stale reference
      assemblies_dropdown = form.find_element(:id, 'study_file_genome_assembly_id')
      assemblies_dropdown.send_keys('GRCh37') # from lib/assets/default_species_assemblies.txt
      sync_button = form.find_element(:class, 'save-study-file')
      sync_button.click
      close_modal('sync-notice-modal')
    end

    # make sure parsing succeeded
    sync_study_path = @base_url + "/study/ideogram-only-#{$random_seed}"
    @driver.get(sync_study_path)
    study_accession = extract_accession_from_url(@driver.current_url)
    loaded_sync_study_path = @base_url + "/study/#{study_accession}/ideogram-only-#{$random_seed}"
    wait_until_page_loads(loaded_sync_study_path)

    # open the 'genome' tab
    open_ui_tab('study-visualize')
    wait_for_render(:css, '#tracks-to-display #filter_1')
    wait_for_render(:id, 'ideogram-container')
    user_ideogram = @driver.execute_script("return $('#_ideogramOuterWrap canvas').length > 0")
    assert user_ideogram, "Ideogram did not render using user token: '$('#_ideogramOuterWrap canvas').length > 0' returned #{user_ideogram}"
    puts "Ensured we can load Ideogram and render its annotations"

    # Log out and validate that we can use the read-only service account to load results (SCP-1856)
    logout_from_portal
    puts "Logged out"

    # Ensure genome visualizations in public studies can be seen by all users (even those not signed-in)
    @driver.get(loaded_sync_study_path)
    open_ui_tab('study-visualize')
    wait_for_render(:css, '#tracks-to-display #filter_1')
    wait_for_render(:id, 'ideogram-container')
    has_ideogram = @driver.execute_script("return $('#_ideogramOuterWrap canvas').length > 0")
    assert has_ideogram, "Ideogram did not render using user token: '$('#_ideogramOuterWrap canvas').length > 0' returned #{user_ideogram}"
    puts "Ensured all users can see ideogram in public studies"

    # clean up
    login_as_other($test_email, $test_email_password)
    @driver.get @base_url + '/studies'
    wait_until_page_loads(@base_url + '/studies')
    delete = @driver.find_element(:class, "ideogram-only-#{$random_seed}-delete-local")
    delete.click
    accept_alert
    close_modal('message_modal')

    puts "#{File.basename(__FILE__)}: '#{self.method_name}' successful!"
  end

  # Test viewing BAM files in igv.js
  test 'front-end: igv bam' do
    puts "#{File.basename(__FILE__)}: '#{self.method_name}'"

    # log in first
    @driver.get @base_url
    login($test_email, $test_email_password)
    @driver.get @base_url + '/studies/new'

    # create a new study using an existing workspace, also generate a random name to validate that workspace name
    # and study name can be different
    random_name = "igv.js UI test #{$random_seed}"
    study_form = @driver.find_element(:id, 'new_study')
    study_form.find_element(:id, 'study_name').send_keys(random_name)
    study_form.find_element(:id, 'study_use_existing_workspace').send_keys('Yes')
    study_form.find_element(:id, 'study_firecloud_workspace').send_keys("development-igv-js-ui-test")
    share = @driver.find_element(:id, 'add-study-share')
    @wait.until {share.displayed?}
    share.click
    share_email = study_form.find_element(:class, 'share-email')
    share_email.send_keys($share_email)

    # save study
    save_study = @driver.find_element(:id, 'save-study')
    save_study.click
    @wait.until {element_present?(:id, 'unsynced-study-files')}
    close_modal('message_modal')

    # sync each file
    study_file_forms = @driver.find_elements(:class, 'unsynced-study-file')
    bam_file = 'fixed_neurons_6days_2000_possorted_genome_bam_test_data.bam'
    study_file_forms.each do |form|
      filename = form.find_element(:id, 'study_file_name')['value']
      if filename == 'cluster_example.txt' or filename == 'expression_matrix_example.txt' or filename == 'metadata_example.txt' or filename == bam_file or bam_file + '.bai'
        file_type = form.find_element(:id, 'study_file_file_type')
        case filename
        when 'cluster_example.txt'
          file_type.send_keys('Cluster')
        when 'expression_matrix_example.txt'
          file_type.send_keys('Expression Matrix')
          species_dropdown = form.find_element(:id, 'study_file_taxon_id')
          opts = species_dropdown.find_elements(:tag_name, 'option')
          available_species = opts.delete_if {|opt| opt['value'] == ''}
          if available_species.any?
            species_dropdown.send_keys(available_species.sample.text)
          end
        when 'metadata_example.txt'
          file_type.send_keys('Metadata')
        when bam_file
          file_type.send_keys('BAM')
          # TODO: Determine where else this is needed, apply there.  See SCP-1572.
          select_option_from_dropdown(form, 'study_file_taxon_id', 'mouse')
          sleep(2) # wait for first assembly to load
          assemblies_dropdown = form.find_element(:id, 'study_file_genome_assembly_id')
          assemblies_dropdown.send_keys('GRCm38') # from lib/assets/default_species_assemblies.txt
        when "#{bam_file + '.bai'}"
          file_type.send_keys('BAM Index')
          bam_target_menu = form.find_element(:id, 'study_file_options_bam_id')
          bam_target_menu.send_keys(bam_file)
        end
        sync_button = form.find_element(:class, 'save-study-file')
        sync_button.click
        close_modal('sync-notice-modal')
      end
    end

    # now assert that forms were re-rendered in synced data panel
    sync_panel = @driver.find_element(:id, 'synced-data-panel-toggle')
    sync_panel.click

    # lastly, check info page to make sure everything did in fact parse and complete
    studies_path = @base_url + '/studies'
    @driver.get studies_path

    show_button = @driver.find_element(:class, "igv-js-ui-test-#{$random_seed}-show")
    show_button.click
    @wait.until {element_present?(:id, 'info-panel')}
    study_url = @driver.current_url
    gene_count = @driver.find_element(:id, 'gene-count').text.to_i
    while gene_count == 0
      @driver.get study_url
      gene_count = @driver.find_element(:id, 'gene-count').text.to_i
    end

    # Go to study, click 'Browse genome' in Downloads tab
    study_path = @base_url + "/study/igv-js-ui-test-#{$random_seed}"
    @driver.get(study_path)
    study_accession = extract_accession_from_url(@driver.current_url)
    loaded_path = @base_url + "/study/#{study_accession}/igv-js-ui-test-#{$random_seed}"
    wait_until_page_loads(loaded_path)
    open_ui_tab('study-download')
    browse_genome_button = @driver.find_element(:class, "track-browse-genome")
    browse_genome_button.click

    # Verify igv.js displays tracks in Explore tab's default view
    wait_for_render(:class, 'igv-track-div')
    igv_displayed = @driver.execute_script("return $('.igv-track-div').length === 4")
    assert igv_displayed, "igv.js did not display 4 tracks in Explore tab's default view"

    # Search for a gene
    gene = @genes.sample
    search_box = @driver.find_element(:id, 'search_genes')
    search_box.send_keys(gene)
    search_box.click
    search_genes = @driver.find_element(:id, 'perform-gene-search')
    search_genes.click

    # Verify igv.js displays tracks in Explore tab's single-gene view
    @wait.until {wait_for_plotly_render('#expression-plots', 'box-rendered')}
    open_ui_tab('genome-tab')
    wait_for_render(:class, 'igv-track-div')
    igv_displayed = @driver.execute_script("return $('.igv-track-div').length === 4")
    assert igv_displayed, "igv.js did not display 4 tracks in Explore tab's single-gene view"
    open_ui_tab('box-or-violin-tab')
    open_ui_tab('genome-tab')
    igv_single_instance = @driver.execute_script("return $('.igv-root-div').length === 1;")
    assert igv_single_instance, "Multiple instances of igv.js are display; only one should be"

    # clean up
    @driver.get studies_path
    wait_until_page_loads(studies_path)
    delete = @driver.find_element(:class, "igv-js-ui-test-#{$random_seed}-delete-local")
    delete.click
    accept_alert
    close_modal('message_modal')

    puts "#{File.basename(__FILE__)}: '#{self.method_name}' successful!"
  end

  ##
  ## CLEANUP
  ## Delete all studies created during the regrssion suite
  ##

  test 'cleanup: delete all test studies' do
    puts "#{File.basename(__FILE__)}: '#{self.method_name}'"

    # log in first
    @driver.get @base_url
    login($test_email, $test_email_password)
    path = @base_url + '/studies'
    @driver.get path

    study_keys = [
        "test-study-#{$random_seed}-delete",
        "private-study-#{$random_seed}-delete",
        "gzip-parse-#{$random_seed}-delete",
        "embargo-study-#{$random_seed}-delete",
        "twod-study-#{$random_seed}-delete",
        "new-project-study-#{$random_seed}-delete",
        "sync-test-#{$random_seed}-delete-local"
    ]

    # delete studies
    study_keys.each do |study_key|
      if element_present?(:class, study_key)
        @driver.find_element(:class, study_key).click
        accept_alert
        close_modal('message_modal')
      end
    end

    puts "#{File.basename(__FILE__)}: '#{self.method_name}' successful!"
  end
end
