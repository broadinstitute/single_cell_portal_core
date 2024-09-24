require "test_helper"

class HomePageLinkTest < ActiveSupport::TestCase

  before(:all) do
    @home_page_link = HomePageLink.create(name: 'Broad Institute', href: 'https://broadinstitute.org')
  end

  teardown do
    HomePageLink.unpublish!
  end

  after(:all) do
    HomePageLink.delete_all
  end

  test 'should publish/unpublish link' do
    assert_nil HomePageLink.published
    HomePageLink.publish_last!
    assert HomePageLink.published.present?
    link = HomePageLink.published
    link.unpublish!
    assert_nil HomePageLink.published
    link.publish!
    assert HomePageLink.published.present?
    HomePageLink.unpublish!
    assert_nil HomePageLink.published
  end

  test 'should reset css/color attributes' do
    @home_page_link.update(css_class: 'foo', bg_color: '#ff0000')
    @home_page_link.reset_css!
    @home_page_link.reload
    assert_equal HomePageLink::DEFAULT_CSS_CLASS, @home_page_link.css_class
    @home_page_link.reset_bg_color!
    @home_page_link.reload
    assert_equal HomePageLink::DEFAULT_BG_COLOR, @home_page_link.bg_color
  end

  test 'should ensure only one link is published' do
    assert_not HomePageLink.published.present?
    HomePageLink.publish_last!
    assert HomePageLink.published.present?
    new_link = HomePageLink.new(name: 'Google', href: 'https://google.com', published: true)
    assert_not new_link.valid?
    assert_includes new_link.errors.attribute_names, :published
  end
end
