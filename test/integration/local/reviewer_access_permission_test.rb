require 'test_helper'
require 'integration_test_helper'
require 'includes_helper'
require 'detached_helper'

# controller-based test to validate ReviewerAccess & ReviewerAccessSession functionality
# uses ActionController::TestCase since ActionDispatch::IntegrationTest doesn't support signed cookies
class ReviewerAccessPermissionTest < ActionController::TestCase
  tests SiteController

  before(:all) do
    @user = FactoryBot.create(:user, test_array: @@users_to_clean)
    @study = FactoryBot.create(:detached_study,
                               name_prefix: 'Reviewer Access Test', public: false, user: @user,
                               test_array: @@studies_to_clean)
    detail = @study.build_study_detail
    detail.update(full_description: "<p>testing</p>")
    @cookie_name = "reviewer_session_#{@study.accession}".to_sym
  end

  setup do
    @study.reload
  end

  teardown do
    ReviewerAccessSession.destroy_all
    ReviewerAccess.destroy_all
    OmniAuth.config.mock_auth[:google_oauth2] = nil
  end

  test 'should create reviewer access' do
    mock_not_detached @study, :find_by do
      auth_as_user(@user)
      sign_in @user
      study_params = {
        accession: @study.accession, study_name: @study.url_safe_name,
        study: {
          reviewer_access_attributes: {
            expires_at: 2.months.from_now.to_date.to_s
          }
        },
        reviewer_access_actions: {
          enable: 'yes'
        }
      }

      post :update_study_settings, params: study_params, xhr: true
      assert_response :success
      @study.reload
      access = @study.reviewer_access
      assert access.present?
      get :reviewer_access, params: { access_code: access.access_code }
      assert_response :success
    end
  end

  test 'should update expiration date' do
    mock_not_detached @study, :find_by do
      access = @study.build_reviewer_access
      access.save!
      new_expiration = access.expires_at + 1.month
      auth_as_user(@user)
      sign_in @user
      study_params = {
        accession: @study.accession, study_name: @study.url_safe_name,
        study: {
          reviewer_access_attributes: {
            expires_at: new_expiration.to_s,
            id: access.id.to_s
          }
        },
        reviewer_access_actions: {
          enable: 'yes'
        }
      }

      post :update_study_settings, params: study_params, xhr: true
      assert_response :success
      access.reload
      assert_equal new_expiration, access.expires_at
    end
  end

  test 'should create new reviewer access session' do
    access = @study.build_reviewer_access
    access.save!
    access_params = { access_code: access.access_code, reviewer_access: { pin: access.pin } }
    post :validate_reviewer_access, params: access_params
    assert_redirected_to view_study_path(accession: @study.accession, study_name: @study.url_safe_name)
    assert cookies.signed[@cookie_name].present?
    access.reload
    assert access.reviewer_access_sessions.any?
  end

  test 'should validate reviewer access' do
    mock_not_detached @study, :find_by do
      access = @study.build_reviewer_access
      access.save!
      original_expires_at = access.expires_at.dup
      auth_as_user(@user)
      sign_in @user
      # blank expires_at should be discarded and ignored
      study_params = {
        accession: @study.accession, study_name: @study.url_safe_name,
        study: {
          reviewer_access_attributes: {
            expires_at: ''
          }
        },
        reviewer_access_actions: {
          enable: 'yes'
        }
      }

      post :update_study_settings, params: study_params, xhr: true
      assert_response :success
      access.reload
      assert_equal original_expires_at, access.expires_at
    end
  end

  test 'should block authentication with invalid pin' do
    access = @study.build_reviewer_access
    access.save!
    access_params = {
      access_code: access.access_code,
      reviewer_access: {
        pin: SecureRandom.alphanumeric(ReviewerAccess::PIN_LENGTH)
      }
    }
    post :validate_reviewer_access, params: access_params
    assert_response :forbidden
    # test very large pin value
    access_params = {
      access_code: access.access_code,
      reviewer_access: {
        pin: SecureRandom.alphanumeric(256)
      }
    }
    post :validate_reviewer_access, params: access_params
    assert_response :forbidden
    refute access.reviewer_access_sessions.any?
  end

  test 'should invalidate reviewer access sessions' do
    mock_not_detached @study, :find_by do
      access = @study.build_reviewer_access
      access.save!
      session = access.create_new_session
      # mock cookie generation since we're not testing the form submission here
      cookies.signed[@cookie_name] = {
        value: session.session_key,
        expires: session.expires_at,
        httponly: true,
        secure: true,
        same_site: :strict
      }
      get :study, params: { accession: @study.accession, study_name: @study.url_safe_name }
      assert_response :success
      auth_as_user(@user)
      sign_in @user
      study_params = {
        accession: @study.accession, study_name: @study.url_safe_name,
        study: {
          reviewer_access_attributes: {
            expires_at: 2.months.from_now.to_date.to_s
          }
        },
        reviewer_access_actions: {
          enable: 'no'
        }
      }

      post :update_study_settings, params: study_params, xhr: true
      assert_response :success
      @study.reload
      refute @study.reviewer_access.present?
      sign_out @user
      OmniAuth.config.mock_auth[:google_oauth2] = nil # gotcha to clear any cached auth responses
      get :study, params: { accession: @study.accession, study_name: @study.url_safe_name }
      assert_redirected_to new_user_session_path
    end
  end

  test 'should rotate credentials and invalidate reviewer access sessions' do
    mock_not_detached @study, :find_by do
      access = @study.build_reviewer_access
      access.save!
      original_access_code = access.access_code.dup
      original_pin = access.pin.dup
      get :reviewer_access, params: { access_code: access.access_code }
      assert_response :success
      get :study, params: { accession: @study.accession, study_name: @study.url_safe_name }
      assert_redirected_to new_user_session_path
      auth_as_user(@user)
      sign_in @user
      reviewer_access_params = {
        accession: @study.accession, study_name: @study.url_safe_name,
        study: {
          reviewer_access_attributes: {
            expires_at: 2.months.from_now.to_date.to_s
          }
        },
        reviewer_access_actions: {
          reset: 'yes'
        }
      }
      post :update_study_settings, params: reviewer_access_params, xhr: true
      assert_response :success
      @study.reload
      access.reload
      assert_not_equal original_access_code, access.access_code
      assert_not_equal original_pin, access.pin
      refute access.reviewer_access_sessions.any?
      sign_out @user
      OmniAuth.config.mock_auth[:google_oauth2] = nil # gotcha to clear any cached auth responses
      get :reviewer_access, params: { access_code: original_access_code }
      assert_redirected_to site_path
      get :study, params: { accession: @study.accession, study_name: @study.url_safe_name }
      assert_redirected_to new_user_session_path
      get :reviewer_access, params: { access_code: access.access_code }
      assert_response :success
    end
  end

  # handles regression found in SCP-3680
  test 'should update study description w/o reviewer access settings' do
    mock_not_detached @study, :find_by do
      auth_as_user(@user)
      sign_in @user
      new_description = "<p>This is the updated description</p>"
      study_params = {
        accession: @study.accession, study_name: @study.url_safe_name,
        study: {
          study_detail_attributes: {
            full_description: new_description,
            id: @study.study_detail.id.to_s
          }
        }
      }
      post :update_study_settings, params: study_params, xhr: true
      assert_response :success
      @study.reload
      assert_equal @study.full_description, new_description
    end
  end
end
