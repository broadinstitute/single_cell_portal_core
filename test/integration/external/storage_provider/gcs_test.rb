require 'test_helper'
require 'detached_helper'

module StorageProvider
  class GcsTest < ActiveSupport::TestCase
    before(:all) do
      @client = StorageProvider::Gcs.new
      @bucket_prefix = "gcs-provider-test-#{SecureRandom.hex(4)}"
      @bucket_name = "#{@bucket_prefix}-#{SecureRandom.hex(8)}"
      @bucket = @client.create_bucket(@bucket_name)
      filename = 'cluster_example.txt'
      @bucket.create_file(
        File.open(Rails.root.join('test', 'test_data', filename)),
        filename
      )
    end
  end

  after(:all) do
    @client.buckets(prefix: @bucket_prefix).map(&:delete)
  end

  test 'should instantiate GCS client' do
    client = StorageProvider::Gcs.new
    assert_equal StorageProvider::Gcs, client.class
    assert_equal ENV['GOOGLE_CLOUD_PROJECT'], client.project
  end

  test 'should get buckets' do
    buckets = @client.buckets(prefix: @bucket_prefix)
    assert buckets.any? { |b| b.name.start_with?(@bucket_prefix) }, 'No buckets found with the expected prefix'
  end

  test 'should get bucket by name' do
    bucket = @client.bucket(@bucket_name)
    assert_equal @bucket_name, bucket.name, 'Bucket name does not match expected name'
  end

  test 'should create a bucket' do
    new_bucket_name = "#{@bucket_prefix}-create-#{SecureRandom.hex(4)}"
    new_bucket = @client.create_bucket(new_bucket_name)
    assert_equal new_bucket_name, new_bucket.name, 'New bucket was not created with the expected name'
  end

  test 'should delete a bucket' do
    new_bucket_name = "#{@bucket_prefix}-delete-#{SecureRandom.hex(4)}"
    new_bucket = @client.create_bucket(new_bucket_name)
    assert new_bucket.present?
    @client.delete_bucket(new_bucket_name)
    assert_raises(Google::Cloud::PermissionDeniedError) do
      @client.get_bucket(new_bucket_name)
    end
  end

  test 'should update bucket acl' do
    email = 'test_user@'
  end

  test 'should list files in bucket' do
    files = @client.bucket_files(@bucket_name)
    assert files.any? { |f| f.name == 'cluster_example.txt' }, 'Expected file not found in bucket'
  end

  test 'should upload a file to bucket' do
    filename = 'workspace_samples.tsv'
    file_path = Rails.root.join('test', 'test_data', filename)
    uploaded_file = @client.create_bucket_file(@bucket_name, file_path, filename)
    assert uploaded_file.present?, 'File upload failed'
    assert_equal filename, uploaded_file.name, 'Uploaded file name does not match expected name'
  end

  test 'should download a file from bucket' do
    filename = 'cluster_example.txt'
    file = @client.bucket_file(@bucket_name, filename)
    assert file.present?, 'File not found in bucket'

    downloaded_content = file.download
    assert downloaded_content.is_a?(StringIO), 'Downloaded content is not a StringIO object'
    assert downloaded_content.string.include?('example content'), 'Downloaded content does not match expected content'
  end
end
