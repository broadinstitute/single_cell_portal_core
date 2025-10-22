require 'test_helper'
require 'integration_test_helper'
require 'includes_helper'

class AdminConfigurationsControllerTest < ActionDispatch::IntegrationTest
  before(:all) do
    @admin = FactoryBot.create(:admin_user, test_array: @@users_to_clean)
    @user = FactoryBot.create(:user, test_array: @@users_to_clean)
  end

  setup do
    sign_in @admin
    auth_as_user @admin
  end

  test 'should not allow creating admin users through UI' do
    patch update_user_path(@user), params: { user: { admin: true } }
    assert_response 302
    @user.reload
    assert_not @user.admin
  end
end
