require 'test_helper'

class ApplicationHelperTest < ActionView::TestCase

  before(:all) do
    @user = FactoryBot.create(:admin_user, test_array: @@users_to_clean)
  end

  test 'should retrieve access token' do
    # store access token to restore later
    access_token_hash = @user.access_token
    client_access_token_hash = get_user_access_token_hash(@user)
    client_access_token = client_access_token_hash.dig(:access_token)
    expected_token = access_token_hash.dig(:access_token)
    assert_equal expected_token, client_access_token,
                 "Access tokens do not match; #{expected_token} != #{client_access_token}"
    refute client_access_token.nil?, "Should have retrieved a value for access token"

    # simulate issue with access token retrieval by clearing values
    @user.update!(access_token: nil)
    @user.reload
    new_token = get_user_access_token_hash(@user).dig(:access_token)
    assert new_token.nil?, "Access token should be nil, but found #{new_token}"
  end
end
