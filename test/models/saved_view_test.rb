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
                                    path: "/single_cell/study/#{@study.accession}")
  end

  test 'should instantiate and validate' do
    saved_view = SavedView.new(
      name: 'My Saved View',
      path: '/single_cell/study/SCP1234',
      user: @user
    )
    assert saved_view.valid?
    invalid_view = SavedView.new(
      name: 'My Favorite Study',
      path: "/single_cell/study/#{@study.accession}",
      user: @user
    )
    assert_not invalid_view.valid?
    errors = invalid_view.errors.full_messages
    assert_equal 2, errors.count
    errors.each do |error|
      assert error.match(/(Name|Path) is already taken/)
    end
    invalid_view.name = nil
    invalid_view.path = nil
    assert_not invalid_view.valid?
    errors = invalid_view.errors.full_messages
    assert_equal 2, errors.count
    errors.each do |error|
      assert error.match(/(Name|Path) can't be blank/)
    end
  end

  test 'should get full href for saved view' do
    expected_href = "#{RequestUtils.get_base_url}/single_cell/study/#{@study.accession}"
    assert_equal expected_href, @saved_view.href
  end
end
