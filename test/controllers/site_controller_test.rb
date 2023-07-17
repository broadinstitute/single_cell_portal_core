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
  end

  test 'should redirect to home page from bare domain' do
    get '/'
    assert_response 302, "Did not receive correct HTTP status code, expected 302 but found #{status}"
    assert_redirected_to site_path, "Did not provide correct redirect, should have gone to #{site_path} but found #{path}"
    follow_redirect!
    assert_equal(site_path, path, "Redirect did not successfully complete, #{site_path} != #{path}")
  end

  test 'should redirect to correct study name url' do
    correct_study_url = view_study_path(accession: @study.accession, study_name: @study.url_safe_name)
    incorrect_study_url = view_study_path(accession: @study.accession, study_name: "bogus_name")
    get incorrect_study_url
    assert_response 302, 'Did not redirect to correct url'
    assert_redirected_to correct_study_url, 'Url did not redirected successfully'
    follow_redirect!
    assert_equal(correct_study_url, path, "Url is #{path}. Expected #{correct_study_url}")
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
    assert_equal site_path, path
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

      private_mock = generate_download_file_mock([file], private: true)
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
      mock.expect :services_available?, true, [String]
      systems = [FireCloudClient::SAM_SERVICE, FireCloudClient::RAWLS_SERVICE, FireCloudClient::BUCKETS_SERVICE]
      ok = { ok: true }
      api_status = {
        systems: Hash[systems.zip(Array.new(3) { ok })]
      }.with_indifferent_access
      mock.expect :api_status, api_status
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
end
