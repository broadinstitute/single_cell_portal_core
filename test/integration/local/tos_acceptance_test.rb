require 'integration_test_helper'
require 'test_helper'
require 'includes_helper'

class TosAcceptanceTest < ActionDispatch::IntegrationTest

  setup do
    @test_user = User.create(email: 'needs.acceptance@gmail.com', password: 'password', uid: '54321',
                             registered_for_firecloud: true)
    sign_in @test_user
    auth_as_user @test_user
  end

  teardown do
    OmniAuth.config.mock_auth[:google_oauth2] = nil
    email = 'needs.acceptance@gmail.com'
    User.find_by(email: email)&.destroy
    TosAcceptance.find_by(email: email)&.destroy
  end

  test 'should record user tos action' do
    @test_user.stub :must_accept_terra_tos?, false do
      # first log in and validate that the user is redirected to the ToS page
      get site_path
      follow_redirect!
      assert path == accept_tos_path(@test_user.id),
             "Did not redirect to terms of service path, current path is #{path}"
      # first deny ToS and validate that user gets signed out
      post record_tos_action_path(id: @test_user.id, tos: {action: 'deny'})
      follow_redirect!
      user_accepted = TosAcceptance.accepted?(@test_user)
      assert_not user_accepted, "Did not record user denial, acceptance shows: #{user_accepted}"
      assert controller.current_user.nil?, "Did not sign out user, current_user is #{controller.current_user}"
      # now accept ToS
      sign_in @test_user
      post record_tos_action_path(id: @test_user.id, tos: {action: 'accept'})
      follow_redirect!
      user_accepted = TosAcceptance.accepted?(@test_user)
      assert user_accepted, "Did not record user acceptance, acceptance shows: #{user_accepted}"
      assert controller.current_user == @test_user,
             "Did not preserve sign in, current user is not #{@test_user.email}"
      # now get another page and validate that redirect is no longer being enforced
      get site_path
      assert path == site_path, "Redirect still being enforced, expected path to be #{site_path} but found #{path}"
    end
  end
end

