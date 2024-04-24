require 'test_helper'

class BookmarkTest < ActiveSupport::TestCase

  before(:all) do
    @user = FactoryBot.create(:user, test_array: @@users_to_clean)
    @study = FactoryBot.create(:detached_study,
                               name_prefix: 'Saved View Test',
                               user: @user,
                               test_array: @@studies_to_clean)
    @bookmark = FactoryBot.create(:bookmark,
                                  user: @user,
                                  study_accession: @study.accession,
                                  name: 'My Favorite Study',
                                  path: "/single_cell/study/#{@study.accession}")
  end

  test 'should instantiate and validate' do
    bookmark = Bookmark.new(
      name: 'My Saved View',
      path: '/single_cell/study/SCP1234',
      study_accession: @study.accession,
      user: @user
    )
    assert bookmark.valid?
    invalid_view = Bookmark.new(
      name: 'My Favorite Study',
      study_accession: @study.accession,
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
end
