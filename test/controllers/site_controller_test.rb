require 'api_test_helper'
require 'integration_test_helper'
require 'test_helper'
require 'includes_helper'
require 'detached_helper'

class SiteControllerTest < ActionDispatch::IntegrationTest

  before(:all) do
    @user = FactoryBot.create(:admin_user, test_array: @@users_to_clean)
    @sharing_user = FactoryBot.create(:user, test_array: @@users_to_clean)
    @study = FactoryBot.create(:detached_study,
                               name_prefix: 'Site Controller Study',
                               public: true,
                               user: @user,
                               test_array: @@studies_to_clean)
    FactoryBot.create(:metadata_file,
                      study: @study,
                      name: 'metadata_example.txt',
                      upload_file_size: 1.megabyte)
    FactoryBot.create(:cluster_file,
                      study: @study,
                      name: 'cluster_example.txt',
                      upload_file_size: 1.megabyte)
    FactoryBot.create(:cluster_file,
                      study: @study,
                      name: 'cluster_example_2.txt',
                      upload_file_size: 1.megabyte)
    detail = @study.build_study_detail
    detail.full_description = '<p>This is the description.</p>'
    detail.save!
  end

  def setup
    auth_as_user(@user)
    sign_in @user
  end

  def teardown
    OmniAuth.config.mock_auth[:google_oauth2] = nil
    # reset public permission
    @study.update(public: true)
    AdminConfiguration.find_by(config_type: 'Daily User Download Quota')&.destroy
    @user.update(daily_download_quota: 0)
    FeatureFlag.find_by(name: 'enable_purchases_ux')&.destroy
    Purchase.destroy_all
    DownloadRequest.destroy_all
  end

  test 'should redirect to home page from bare domain' do
    get '/'
    assert_response 302, "Did not receive correct HTTP status code, expected 302 but found #{status}"
    assert_redirected_to site_path, "Did not provide correct redirect, should have gone to #{site_path} but found #{path}"
    follow_redirect!
    assert_equal(site_path, path, "Redirect did not successfully complete, #{site_path} != #{path}")
  end

  test 'should load study from correct accession and preserve params' do
    correct_study_url = view_study_path(accession: @study.accession, study_name: @study.url_safe_name)
    incorrect_study_url = view_study_path(accession: @study.accession, study_name: "bogus_name")
    get incorrect_study_url
    assert_response 200
    assert path.include?(@study.accession)
    assert path.include?('bogus_name'), 'did not ignore incorrect name in path'
    legacy_path = legacy_study_path(identifier: @study.accession)
    get legacy_path
    assert_redirected_to correct_study_url, 'Url did not redirected successfully'
    follow_redirect!
    # test query param persistence
    assert_equal(correct_study_url, path, "Url is #{path}. Expected #{correct_study_url}")
    path_with_params = legacy_study_path(identifier: @study.accession, genes: 'GAD1')
    get path_with_params
    assert_response 302
    follow_redirect!
    assert_equal request.query_string, 'genes=GAD1', "did not preserve query parameters: #{request.fullpath}"
  end

  test 'should create and delete deployment notification banner' do
    deployment_notification_params = {
      deployment_notification: {
        deployment_time: Time.zone.now,
        message: 'Testing deployment notification banner'
      }
    }

    post create_deployment_notification_path, params: deployment_notification_params, xhr: true
    get site_path
    assert_select '.notification-banner', 1,"Notification banner did not render to page"
    delete delete_deployment_notification_path
    follow_redirect!
    assert_response 200, 'Did not redirect successfully after banner was deleted'
    # Ensure page does not contain notification banner
    assert_select ".notification-banner", false, "Notification banner was not deleted and still is present on page."
  end

  test 'should control access to private studies' do
    get view_study_path(accession: @study.accession, study_name: @study.url_safe_name)
    assert_response :success

    # set to private, validate study owner/admin can still access
    @study.update(public: false)
    get view_study_path(accession: @study.accession, study_name: @study.url_safe_name)
    assert_response :success

    # negative tests
    sign_out(@user)
    get view_study_path(accession: @study.accession, study_name: @study.url_safe_name)
    assert_response 302
    follow_redirect!
    assert_equal new_user_session_path, path

    auth_as_user(@sharing_user)
    sign_in @sharing_user

    get view_study_path(accession: @study.accession, study_name: @study.url_safe_name)
    assert_response 302
    follow_redirect!
    assert_equal redacted_study_path(@study.accession), path
  end

  test 'should control access to files in private studies' do
    mock_not_detached @study, :find_by do
      file = @study.study_files.sample
      public_mock = generate_download_file_mock([file])
      ApplicationController.stub :firecloud_client, public_mock do
        get download_file_path(accession: @study.accession, study_name: @study.url_safe_name, filename: file.upload_file_name)
        assert_response 302
        # since this is an external redirect, we cannot call follow_redirect! but instead have to get the location header
        signed_url = response.headers['Location']
        assert signed_url.include?(file.upload_file_name), 'Redirect url does not point at requested file'
        public_mock.verify
      end

      private_mock = generate_download_file_mock([file])
      ApplicationController.stub :firecloud_client, private_mock do
        # set to private, validate study owner/admin can still access
        # note that download_file_path and download_private_file_path both resolve to the same method and enforce the same
        # restrictions; both paths are preserved for legacy redirects from published papers
        @study.update(public: false)
        get download_private_file_path(accession: @study.accession, study_name: @study.url_safe_name, filename: file.upload_file_name)
        assert_response 302
        signed_url = response.headers['Location']
        assert signed_url.include?(file.upload_file_name), 'Redirect url does not point at requested file'
        private_mock.verify
      end

      # negative tests
      sign_out(@user)
      get download_private_file_path(accession: @study.accession, study_name: @study.url_safe_name, filename: file.upload_file_name)
      assert_response 302
      follow_redirect!
      assert_equal new_user_session_path, path, 'Did not redirect to sign in page'

      auth_as_user(@sharing_user)
      sign_in @sharing_user

      get download_private_file_path(accession: @study.accession, study_name: @study.url_safe_name, filename: file.upload_file_name)
      assert_response 302
      follow_redirect!
      assert_equal site_path, path, 'Did not redirect to home page'
    end
  end

  test 'should enforce download quota for files' do
    AdminConfiguration.find_or_create_by(
      config_type: 'Daily User Download Quota', value: '1', value_type: 'Numeric', multiplier: 'kilobyte'
    )
    mock_not_detached @study, :find_by do
      file = @study.study_files.sample
      mock = Minitest::Mock.new
      file_mock = Minitest::Mock.new
      file_mock.expect :present?, true
      file_mock.expect :size, file.upload_file_size
      mock.expect :execute_gcloud_method, file_mock, [:get_workspace_file, 0, String, String]
      ApplicationController.stub :firecloud_client, mock do
        download = download_file_path(
          accession: @study.accession, study_name: @study.url_safe_name, filename: file.upload_file_name
        )
        get download
        assert_response 302
        follow_redirect!
        assert_equal view_study_path(@study.accession, @study.url_safe_name), path
        mock.verify
        file_mock.verify
      end
    end
  end

  test 'should save/delete author and publication data from study settings tab' do
    mock_not_detached @study, :find_by do
      assert @study.authors.empty?
      assert @study.publications.empty?
      study_params = {
        'study' => {
          'authors_attributes' => {
            '0' => {
              'first_name' => 'Joe',
              'last_name' => 'Smith',
              'email' => 'j.smith@test.edu',
              'institution' => 'Test University',
              'corresponding' => '1',
              '_destroy' => 'false'
            }
          },
          'publications_attributes' => {
            '0' => {
              'title' => 'Div-Seq: Single nucleus RNA-Seq reveals dynamics of rare adult newborn neurons',
              'journal' => 'Science',
              'pmcid' => 'PMC5480621',
              'citation' => 'Science. 2016 Aug 26; 353(6302): 925‚Äì928. Published online 2016 Jul 28.',
              'url' => 'https://www.science.org/doi/10.1126/science.aad7038',
              'preprint' => '0',
              '_destroy' => 'false'
            }
          }
        }
      }
      patch update_study_settings_path(accession: @study.accession, study_name: @study.url_safe_name),
            params: study_params, xhr: true
      assert_response :success
      @study.reload
      assert @study.authors.count == 1
      assert @study.authors.corresponding.count == 1
      assert @study.publications.count == 1
      assert @study.publications.published.count == 1
      author_id = @study.authors.first.id.to_s
      publication_id = @study.publications.first.id.to_s
      # test delete functionality
      study_params = {
        'study' => {
          'authors_attributes' => {
            '0' => {
              'id' => author_id,
              '_destroy' => 'true'
            }
          },
          'publications_attributes' => {
            '0' => {
              'id' => publication_id,
              '_destroy' => 'true'
            }
          }
        }
      }
      patch update_study_settings_path(accession: @study.accession, study_name: @study.url_safe_name),
            params: study_params, xhr: true
      assert_response :success
      @study.reload
      assert @study.authors.empty?
      assert @study.publications.empty?
    end
  end

  test 'should reorder clusterings based on study settings' do
    assert_equal %w[cluster_example.txt cluster_example_2.txt], @study.default_cluster_order
    mock_not_detached @study, :find_by do
      study_params = {
        study: {
          default_options: {
            cluster_order: %w[cluster_example_2.txt cluster_example.txt]
          }
        }
      }.with_indifferent_access
      patch update_study_settings_path(accession: @study.accession, study_name: @study.url_safe_name),
            params: study_params, xhr: true
      assert_response :success
      @study.reload
      assert_equal %w[cluster_example_2.txt cluster_example.txt], @study.default_cluster_order
    end
  end

  test 'should show home page link' do
    get site_path
    assert_select '#home-page-link', 0
    HomePageLink.create(name: 'Foo', href: 'http://foo.com', published: true)
    get site_path
    assert_select '#home-page-link', 1
    HomePageLink.delete_all
  end

  test 'should load study redaction page' do
    # should redirect to study if not redacted
    get redacted_study_path(accession: @study.accession)
    follow_redirect!
    assert_equal view_study_path(accession: @study.accession, study_name: @study.url_safe_name),
                 path,
                 'Did not redirect to home page for non-redacted study'
    Study.stub :find_by, @study do
      @study.stub :redacted?, true do
        get redacted_study_path(accession: @study.accession)
        assert_response :success
        assert_equal redacted_study_path(accession: @study.accession), path
        assert_select '#redaction-notice', 1, 'Redacted study message not found on page'
      end
    end
  end

  test 'should create data egress checkout session for file' do
    FeatureFlag.create(name: 'enable_purchases_ux', default_value: true)
    AdminConfiguration.find_or_create_by(
      config_type: 'Daily User Download Quota', value: '1', value_type: 'Numeric', multiplier: 'gigabyte'
    )
    study = FactoryBot.create(:detached_study,
                               name_prefix: 'Data Egress Study',
                               public: true,
                               user: @user,
                               test_array: @@studies_to_clean)
    study_file = FactoryBot.create(:study_file,
                                    study:,
                                    file_type: 'Other',
                                    name: 'other.txt',
                                    upload_file_size: 10.gigabytes)
    
    data_egress_params = { 
      success_path: "/single_cell/data/egress/#{study.accession}/#{study_file.id}/success",
      accession: study.accession,
      gb_excess: 9,
      download_identifier: study_file.id.to_s
    }
    mock = Minitest::Mock.new
    mock_product = Minitest::Mock.new
    mock_product.expect :name, 'Data Egress Charge'
    mock_product.expect :nil?, false
    mock_product.expect :id, 'prod_12345'
    # since it is not feasible to create a real checkout session in the test environment, 
    # we will instead have the URL be the success page to simulate a completed checkout session
    mock_session = Minitest::Mock.new
    mock_session.expect :url, data_egress_params[:success_path]
    mock_session.expect :success_url, data_egress_params[:success_path]

    mock.expect :products, [mock_product]
    mock.expect :create_data_egress_checkout_session, 
                mock_session,
                ['prod_12345', @user, Integer, Hash]

    mock_not_detached study, :find_by do
      StripeApiClient.stub :new, mock do
        post data_egress_checkout_path(accession: study.accession, download_identifier: study_file.id), params: { data_egress: data_egress_params }
        assert_response 303
        follow_redirect!
        assert_equal data_egress_params[:success_path], path, "Did not redirect to correct success page, expected #{data_egress_params[:success_path]} but found #{path}"
        # create a purchase record to simulate a completed checkout session
        purchase = Purchase.create!(
          name: 'Data Egress Charge',
          study_accession: study.accession,
          customer_email: @user.email,
          checkout_session_id: "co_test_#{SecureRandom.alphanumeric(24)}",
          payment_intent_id: "pi_#{SecureRandom.alphanumeric(24)}",
          download_identifier: study_file.id.to_s,
          sale_date: DateTime.now.in_time_zone,
          amount: 1.08,
          payment_status: 'paid',
          fulfilled: false
        )
        download_mock = generate_download_file_mock([study_file])
        ApplicationController.stub :firecloud_client, download_mock do
          get download_file_path(accession: study.accession, study_name: study.url_safe_name, filename: study_file.upload_file_name)
          assert_response 302
          signed_url = response.headers['Location']
          assert signed_url.include?(study_file.upload_file_name), 'Redirect url does not point at requested file'
          download_mock.verify
          # verify that the purchase record is marked as fulfilled
          purchase.reload
          assert purchase.fulfilled?, 'Purchase record was not marked as fulfilled after download'
          @user.reload
          assert_equal 10.gigabytes, @user.daily_download_quota, 'User download quota was not updated correctly after download'
        end
      end
    end
  end

  test 'should create data egress checkout session for bulk download' do
    FeatureFlag.create(name: 'enable_purchases_ux', default_value: true)
    AdminConfiguration.find_or_create_by(
      config_type: 'Daily User Download Quota', value: '1', value_type: 'Numeric', multiplier: 'gigabyte'
    )
    study = FactoryBot.create(:detached_study,
                               name_prefix: 'Data Egress Bulk Study',
                               public: true,
                               user: @user,
                               test_array: @@studies_to_clean)
    5.times do |i|
      FactoryBot.create(:study_file,
                         study:,
                         file_type: 'Other',
                         name: "file_#{i}.txt",
                         upload_file_size: 5.gigabytes)
    end  
    # start bulk download process to create DownloadRequest                         
    get data_egress_start_path(accession: study.accession, download_identifier: 'bulk')
    assert_response :success
    @user.reload
    download_request = DownloadRequest.find_by(user_id: @user.id, auth_code: @user.totat)
    assert download_request.present?
    data_egress_params = { 
      success_path: "/single_cell/data/egress/#{study.accession}/#{download_request.id}/success",
      accession: study.accession,
      gb_excess: 24,
      download_identifier: download_request.id.to_s
    }
    mock = Minitest::Mock.new
    mock_product = Minitest::Mock.new
    mock_product.expect :name, 'Data Egress Charge'
    mock_product.expect :nil?, false
    mock_product.expect :id, 'prod_12345'
    # since it is not feasible to create a real checkout session in the test environment, 
    # we will instead have the URL be the success page to simulate a completed checkout session
    mock_session = Minitest::Mock.new
    mock_session.expect :url, data_egress_params[:success_path]
    mock_session.expect :success_url, data_egress_params[:success_path]

    mock.expect :products, [mock_product]
    mock.expect :create_data_egress_checkout_session, 
                mock_session,
                ['prod_12345', @user, Integer, Hash]
    StripeApiClient.stub :new, mock do
      post data_egress_checkout_path(accession: study.accession, download_identifier: download_request.id), params: { data_egress: data_egress_params }
      assert_response 303
      follow_redirect!
      mock.verify
      assert_equal data_egress_params[:success_path], path, "Did not redirect to correct success page, expected #{data_egress_params[:success_path]} but found #{path}"
      # create a purchase record to simulate a completed checkout session
      purchase = Purchase.create!(
        name: 'Data Egress Charge',
        study_accession: study.accession,
        customer_email: @user.email,
        checkout_session_id: "co_test_#{SecureRandom.alphanumeric(24)}",
        payment_intent_id: "pi_#{SecureRandom.alphanumeric(24)}",
        download_identifier: download_request.id.to_s,
        sale_date: DateTime.now.in_time_zone,
        amount: 2.88,
        payment_status: 'paid',
        fulfilled: false
      )
      downloads = Minitest::Mock.new
      study.study_files.each do |file|
        bucket_id = study.bucket_id
        file_location = file.bucket_location
        url = "https://www.googleapis.com/storage/v1/b/#{bucket_id}/#{file_location}"
        downloads.expect :execute_gcloud_method, url, [:generate_signed_url, Integer, String, String], expires: 1.day.to_i
      end
      mock_query_not_detached [study] do
        FireCloudClient.stub :new, downloads do
          Api::V1::BulkDownloadController.stub :load_study_files, study.study_files do
            get api_v1_bulk_download_generate_curl_config_path(accession: study.accession, download_id: download_request.id, auth_code: download_request.auth_code)
            assert_response :success
            study.study_files.each do |file|
              assert json.include? file.upload_file_name
            end
            downloads.verify
            # verify that the purchase record is marked as fulfilled
            purchase.reload
            assert purchase.fulfilled?, 'Purchase record was not marked as fulfilled after download'
            @user.reload
            assert_equal 25.gigabytes, @user.daily_download_quota, 'User download quota was not updated correctly after download'
          end
        end
      end
    end
  end
end
