require 'test_helper'

class SavedViewTest < ActiveSupport::TestCase

  before(:all) do
    @user = FactoryBot.create(:user, test_array: @@users_to_clean)
    @study = FactoryBot.create(:detached_study,
                               name_prefix: 'Saved View Test',
                               user: @user,
                               test_array: @@studies_to_clean)
    @saved_view = FactoryBot.create(:saved_view,
                                    user: @user,
                                    name: 'My Favorite Study',
                                    path: "/study/#{@study.accession}")
  end
end
