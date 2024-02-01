require 'api_test_helper'
require 'user_tokens_helper'
require 'test_helper'
require 'includes_helper'

class SavedViewsControllerTest < ActionDispatch::IntegrationTest
  before(:all) do
    @user = FactoryBot.create(:api_user, test_array: @@users_to_clean)
    @study = FactoryBot.create(:detached_study,
                               name_prefix: 'SavedView Controller Test',
                               user: @user,
                               test_array: @@studies_to_clean)
    @saved_view = FactoryBot.create(:saved_view,
                                    user: @user,
                                    name: 'My Favorite Study',
                                    path: "/study/#{@study.accession}")
  end
end
