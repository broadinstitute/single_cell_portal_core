require 'api_test_helper'
require 'user_helper'
require 'test_helper'
require 'includes_helper'

class UserAnnotationsControllerTest < ActionDispatch::IntegrationTest

  before(:all) do
    @user = FactoryBot.create(:api_user, test_array: @@users_to_clean)
    @user2 = FactoryBot.create(:api_user, test_array: @@users_to_clean)
    @study = FactoryBot.create(:detached_study,
                               name_prefix: 'UserAnnotation Study',
                               public: false,
                               user: @user,
                               test_array: @@studies_to_clean)
    @study_file = FactoryBot.create(:cluster_file,
                               name: 'clusterA.txt',
                               study: @study)
  end

  test 'enforces permissions' do
    execute_http_request(:post, api_v1_study_user_annotations_path(@study))
    assert_equal 401, response.status

    sign_in_and_update(@user2)
    execute_http_request(:post, api_v1_study_user_annotations_path(@study), user: @user2)
    assert_equal 403, response.status
  end
end
