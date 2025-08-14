require 'test_helper'
require 'user_helper'

class StorageServiceTest < ActiveSupport::TestCase
  TESTING_CLIENTS = [StorageProvider::Gcs].freeze

  before(:all) do
    @user = gcs_bucket_test_user
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

  test 'should instantiate public access client for study' do
    client = StorageService.load_client(study: @study, public_access: true)
    configured_class = Rails.configuration.storage_client.constantize
    assert client.is_a?(configured_class)
    assert_equal @study.cloud_project, client.project
    assert_equal client.service_account_credentials, client.class.get_read_only_keyfile
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
    mock.expect :location, StorageProvider::Gcs::COMPUTE_REGION
    mock.expect :create_study_bucket,
                Google::Cloud::Storage::Bucket,
                [@study.bucket_id],
                **{ location: StorageProvider::Gcs::COMPUTE_REGION }
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
    client = StorageService.load_client(study: @study)
    client.stub :get_bucket, Google::Cloud::Storage::Bucket do
      client.load_study_bucket(@study.bucket_id)
    end
  end

  test 'should check if study bucket exists' do
    client = StorageService.load_client(study: @study)
    client.stub :get_bucket, Google::Cloud::Storage::Bucket do
      assert client.bucket_exists?(@study.bucket_id)
    end
  end

  test 'should delete all files and bucket for study' do
    file_list_mock = Minitest::Mock.new
    files = []
    20.times do
      file_mock = Minitest::Mock.new
      file_mock.expect :size, Integer
      file_mock.expect :delete, nil
      files << file_mock
    end
    file_list_mock.expect :to_a, files
    mock = Minitest::Mock.new
    mock.expect :get_study_bucket_files, file_list_mock, [@study.bucket_id]
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
      StorageService.remove_bucket_user_share(client, @study, new_share)
      mock.verify
      new_share.destroy
    end
  end

  test 'should list files in study bucket' do
    client = StorageService.load_client(study: @study)
    client.stub :bucket_files, Google::Cloud::Storage::File::List do
      client.get_study_bucket_files(@study.bucket_id)
    end
  end

  test 'should get file in study bucket' do
    client = StorageService.load_client(study: @study)
    client.stub :bucket_file, Google::Cloud::Storage::File do
      client.get_study_bucket_file(@study.bucket_id, @study_file.upload_file_name)
    end
  end

  test 'should check if study file exists in bucket' do
    client = StorageService.load_client(study: @study)
    client.stub :bucket_file_exists?, true do
      assert client.study_bucket_file_exists?(@study.bucket_id, @study_file.upload_file_name)
    end
  end

  test 'should upload file to study bucket' do
    file_mock = Minitest::Mock.new
    2.times { file_mock.expect :generation, '1234567890' }
    mock = Minitest::Mock.new
    mock.expect :create_study_bucket_file,
                file_mock,
                [@study.bucket_id, @study_file.upload.path, @study_file.upload_file_name]
    run_test_for_clients(mock) do
      FileParseService.stub :compress_file_for_upload, false do
        Delayed::Job.stub :enqueue, true do
          client = StorageService.load_client(study: @study)
          StorageService.upload_study_file(client, @study, @study_file)
          mock.verify
        end
      end
    end
  end

  test 'should copy a file in study bucket' do
    client = StorageService.load_client(study: @study)
    client.stub :copy_bucket_file, Google::Cloud::Storage::File do
      assert client.copy_study_bucket_file(@study.bucket_id, @study_file.upload_file_name, 'new_file.txt')
    end
  end

  test 'should generate signed URL for study file' do
    mock = Minitest::Mock.new
    filepath = 'path/to/file.txt'
    signed_url = "https://storage.googleapis.com/#{@study.bucket_id}/#{filepath}"
    mock.expect :signed_url_for_bucket_file, signed_url, [@study.bucket_id, @study_file.upload_file_name], expires: 15
    run_test_for_clients(mock) do
      client = StorageService.load_client(study: @study)
      StorageService.get_signed_url(client, @study, @study_file)
      mock.verify
    end
  end

  test 'should generate media URL for study file' do
    mock = Minitest::Mock.new
    mock.expect :api_url_for_bucket_file,
                "https://www.googleapis.com/storage/v1/b/#{@study.bucket_id}/o/path/to/file.txt",
                [@study.bucket_id, @study_file.upload_file_name]
    run_test_for_clients(mock) do
      client = StorageService.load_client(study: @study)
      StorageService.get_api_url(client, @study, @study_file)
      mock.verify
    end
  end

  test 'should delete study file from bucket' do
    client = StorageService.load_client(study: @study)
    client.stub :delete_bucket_file, true do
      assert client.delete_study_bucket_file(@study.bucket_id, @study_file.bucket_location)
    end
  end

  test 'should read a study file into memory from bucket' do
    client = StorageService.load_client(study: @study)
    client.stub :read_bucket_file, StringIO do
      assert client.read_study_bucket_file(@study.bucket_id, @study_file.bucket_location)
    end
  end

  test 'should validate client class' do
    assert_raises(ArgumentError) do
      StorageService.validate_client('NoClass')
    end
  end
end
