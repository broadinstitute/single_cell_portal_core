require 'test_helper'
require 'detached_helper'

class BucketAccessServiceTest < ActiveSupport::TestCase
  before(:all) do
    @user = FactoryBot.create(:user, test_array: @@users_to_clean)
    @non_access_user = FactoryBot.create(:user, test_array: @@users_to_clean)
    @study = FactoryBot.create(:detached_study,
                               name_prefix: 'BucketAccessService Study',
                               public: false,
                               user: @user,
                               test_array: @@studies_to_clean)
    @file_details = {
      location: '_scp_internal/differential_expression/cluster_diffexp_txt--disease--measles--cluster--wilcoxon.tsv',
      size: 1.megabyte
    }
    @public_study = FactoryBot.create(:detached_study,
                                      name_prefix: 'Public BucketAccessService Study',
                                      user: @user,
                                      test_array: @@studies_to_clean)
  end

  test 'should access correct client' do
    assert_equal ApplicationController.firecloud_client, BucketAccessService.client
  end

  test 'should generate signed url for file' do
    mock = assign_bucket_access_mock!(@file_details, @study)
    ApplicationController.stub :firecloud_client, mock do
      signed_url_info = BucketAccessService.signed_url_for(@file_details[:location], @study)
      assert signed_url_info[:url].include?(@file_details[:location])
      assert_equal @file_details[:size], signed_url_info[:size]
      assert_equal 'cluster_diffexp_txt--disease--measles--cluster--wilcoxon.tsv', signed_url_info[:basename]
      mock.verify
    end
  end

  test 'should determine if user has access' do
    assert BucketAccessService.user_has_access?(@study, @user)
    assert_not BucketAccessService.user_has_access?(@study, @non_access_user)
    assert BucketAccessService.user_has_access?(@public_study, @user)
    assert BucketAccessService.user_has_access?(@public_study, @non_access_user)
  end

  test 'should check if file exists' do
    good_mock = Minitest::Mock.new
    good_mock.expect :workspace_file_exists?, true, [String, String]
    ApplicationController.stub :firecloud_client, good_mock do
      assert BucketAccessService.remote_exists?(@file_details[:location], @study)
      good_mock.verify
    end
    bad_mock = Minitest::Mock.new
    bad_mock.expect :workspace_file_exists?, false, [String, String]
    ApplicationController.stub :firecloud_client, bad_mock do
      assert_not BucketAccessService.remote_exists?(@file_details[:location], @study)
      bad_mock.verify
    end
  end
end
