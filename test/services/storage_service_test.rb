require 'test_helper'

class StorageServiceTest < ActiveSupport::TestCase
  TESTING_CLIENTS = [StorageProvider::Gcs].freeze

  before(:all) do
    @user = FactoryBot.create(:user, test_array: @@users_to_clean)
    @study = FactoryBot.create(:detached_study,
                               name_prefix: 'Storage Service Test',
                               public: true,
                               user: @user,
                               test_array: @@studies_to_clean)
    @share_user = 'someone@example.net'
    @share = @study.study_shares.create(email: @share_user, permission: 'View')
  end

  def run_test_for_clients(mock, &block)
    TESTING_CLIENTS.each do |client_class|
      puts "Testing client: #{client_class}"
      client_class.stub(:new, mock, &block)
    end
  end

  test 'should instantiate client for study' do
    client = StorageService.load_client(study: @study)
    configured_class = Rails.configuration.storage_client.constantize
    assert client.is_a?(configured_class)
    assert_equal @study.cloud_project, client.project
  end

  test 'should call client method' do
    mock = Minitest::Mock.new
    mock.expect(:buckets, [Google::Cloud::Storage::Bucket])
    run_test_for_clients(mock) do
      client = StorageService.load_client
      StorageService.call_client(client, :buckets)
      mock.verify
    end
  end

  test 'should create study bucket and set acls' do
    mock = Minitest::Mock.new
    mock.expect :create_study_bucket, Google::Cloud::Storage::Bucket, [@study.bucket_id]
    mock.expect :enable_bucket_autoclass, Google::Cloud::Storage::Bucket, [@study.bucket_id]
    mock.expect :update_bucket_acl, "user-#{@user.email}", [@study.bucket_id, @user.email, :writer]
    mock.expect :update_bucket_acl, "user-#{@user.email}", [@study.bucket_id, @share_user, :reader]
    run_test_for_clients(mock) do
      client = StorageService.load_client(study: @study)
      StorageService.create_study_bucket(client, @study)
      mock.verify
    end
  end

  test 'should delete all files and bucket for study' do
    file_mock = Minitest::Mock.new
    20.times do
      file_mock.expect :delete, nil
    end
    mock = Minitest::Mock.new
    mock.expect :load_study_bucket_files, file_mock, [@study.bucket_id]
    mock.expect :delete_study_bucket, nil, [@study.bucket_id]
    run_test_for_clients(mock) do
      client = StorageService.load_client(study: @study)
      StorageService.remove_study_bucket(client, @study)
      mock.verify
      file_mock.verify
    end
  end
end
