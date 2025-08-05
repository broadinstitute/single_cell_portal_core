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
    @study_file = FactoryBot.create(:study_file, file_type: 'Other', name: 'README.txt', study: @study)
    @share_user = 'someone@example.net'
    @share = @study.study_shares.create(email: @share_user, permission: 'View')
  end

  def run_test_for_clients(mock, &block)
    @study.reload # refresh state as shares change which can cause downstream issues
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
    bucket_acl_mock = Minitest::Mock.new
    bucket_acl_mock.expect :writers, []
    bucket_acl_mock.expect :readers, []
    mock.expect :get_study_bucket_acl, bucket_acl_mock, [@study.bucket_id]
    mock.expect :update_study_bucket_acl,
                "user-#{@user.email}",
                [@study.bucket_id, @user.email],
                role: :writer
    mock.expect :update_study_bucket_acl,
                "user-#{@user.email}",
                [@study.bucket_id, @share_user],
                role: 'reader'
    run_test_for_clients(mock) do
      client = StorageService.load_client(study: @study)
      StorageService.create_study_bucket(client, @study)
      mock.verify
    end
  end

  test 'should get study bucket' do
    mock = Minitest::Mock.new
    mock.expect :get_bucket, Google::Cloud::Storage::Bucket, [@study.bucket_id]
    run_test_for_clients(mock) do
      client = StorageService.load_client(study: @study)
      StorageService.call_client(client, :load_study_bucket, @study.bucket_id)
      mock.verify
    end
  end

  test 'should delete all files and bucket for study' do
    file_list_mock = Minitest::Mock.new
    files = []
    20.times do
      file_mock = Minitest::Mock.new
      file_mock.expect :delete, nil
      files << file_mock
    end
    file_list_mock.expect :to_a, files
    mock = Minitest::Mock.new
    mock.expect :load_study_bucket_files, file_list_mock, [@study.bucket_id]
    mock.expect :delete_study_bucket, nil, [@study.bucket_id]
    run_test_for_clients(mock) do
      client = StorageService.load_client(study: @study)
      StorageService.remove_study_bucket(client, @study)
      mock.verify
      file_list_mock.verify
      files.map(&:verify)
    end
  end

  test 'should update study bucket ACLs' do
    bucket_acl_mock = Minitest::Mock.new
    @study.study_shares.can_edit.count.times { bucket_acl_mock.expect :writers, [] }
    bucket_acl_mock.expect :readers, []
    mock = Minitest::Mock.new
    mock.expect :get_study_bucket_acl, bucket_acl_mock, [@study.bucket_id]
    mock.expect :update_study_bucket_acl,
                "user-#{@user.email}",
                [@study.bucket_id, @user.email],
                role: :writer
    mock.expect :update_study_bucket_acl,
                "user-#{@share_user}",
                [@study.bucket_id, @share_user],
                role: 'reader'
    run_test_for_clients(mock) do
      client = StorageService.load_client(study: @study)
      StorageService.set_study_bucket_acl(client, @study)
      mock.verify
      bucket_acl_mock.verify
    end
  end

  test 'should remove user share from study bucket' do
    new_user = "user-#{SecureRandom.hex(4)}@example.net"
    new_share = @study.study_shares.create(email: new_user, permission: 'Edit')
    mock = Minitest::Mock.new
    mock.expect :update_study_bucket_acl,
                ["user-#{@user.email}"],
                [@study.bucket_id, new_user],
                role: nil, delete: true
    run_test_for_clients(mock) do
      client = StorageService.load_client(study: @study)
      StorageService.remove_user_share(client, @study, new_share)
      mock.verify
      new_share.destroy
    end
  end

  test 'should generate signed URL for study file' do
    mock = Minitest::Mock.new
    filepath = 'path/to/file.txt'
    signed_url = "https://storage.googleapis.com/#{@study.bucket_id}/#{filepath}"
    mock.expect :download_bucket_file, signed_url, [@study.bucket_id, @study_file.upload_file_name], expires: 15
    run_test_for_clients(mock) do
      client = StorageService.load_client(study: @study)
      StorageService.download_study_file(client, @study, @study_file)
      mock.verify
    end
  end

  test 'should generate media URL for study file' do
    mock = Minitest::Mock.new
    mock.expect :stream_bucket_file,
                "https://www.googleapis.com/storage/v1/b/#{@study.bucket_id}/o/path/to/file.txt",
                [@study.bucket_id, @study_file.upload_file_name]
    run_test_for_clients(mock) do
      client = StorageService.load_client(study: @study)
      StorageService.stream_study_file(client, @study, @study_file)
      mock.verify
    end
  end

  test 'should validate client class' do
    assert_raises(ArgumentError) do
      StorageService.validate_client('NoClass')
    end
  end
end
