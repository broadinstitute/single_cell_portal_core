require 'test_helper'

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

    after(:all) do
      @client.buckets(prefix: @bucket_prefix).each do |bucket|
        bucket.files.each(&:delete)
        bucket.delete
      end
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
      bucket = @client.get_bucket(@bucket_name)
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
      assert_nil @client.get_bucket(new_bucket_name)
    end

    test 'should get bucket acl' do
      acl = @client.get_bucket_acl(@bucket_name)
      assert acl.readers.any? { |entry| entry =~ /project-viewers-/ }, 'Default project-viewers entry not found'
    end

    test 'should update bucket acl' do
      email = 'user@test.com'
      role = :reader
      updated_entity = @client.update_bucket_acl(@bucket_name, email, role:)
      assert_equal "user-#{email}", updated_entity, 'Updated entity does not match expected format'
      acl = @client.get_bucket_acl(@bucket_name)
      assert acl.readers.detect { |entry| entry == "user-#{email}" }, 'ACL entry not found'
      @client.update_bucket_acl(@bucket_name, email, role:, delete: true)
      updated_acl = @client.get_bucket_acl(@bucket_name)
      assert updated_acl.readers.detect { |entry| entry == "user-#{email}" }.nil?
    end

    test 'should set bucket autoclass' do
      new_bucket_name = "#{@bucket_prefix}-autoclass-#{SecureRandom.hex(4)}"
      new_bucket = @client.create_bucket(new_bucket_name)
      assert new_bucket.present?, 'New bucket was not created'
      @client.enable_bucket_autoclass(new_bucket_name, terminal_storage_class: 'NEARLINE')
      updated_bucket = @client.get_bucket(new_bucket_name)
      assert_equal 'NEARLINE', updated_bucket.autoclass.terminal_storage_class,
                   'Autoclass was not correctly configured on the new bucket'
    end

    test 'should list files in bucket' do
      files = @client.bucket_files(@bucket_name)
      assert files.any? { |f| f.name == 'cluster_example.txt' }, 'Expected file not found in bucket'
    end

    test 'should upload a file to bucket' do
      filename = 'workspace_samples.tsv'
      uploaded_file = @client.create_bucket_file(@bucket_name, File.open(Rails.root.join("test/test_data/#{filename}")), filename)
      assert uploaded_file.present?, 'File upload failed'
      assert_equal filename, uploaded_file.name, 'Uploaded file name does not match expected name'
    end

    test 'should read a file from bucket' do
      filename = 'cluster_example.txt'
      file_content = @client.read_bucket_file(@bucket_name, filename)
      assert file_content.present?, 'File not found in bucket'
      assert file_content.is_a?(StringIO), 'Downloaded content is not a StringIO object'
      assert file_content.string.include?("NAME\tX\tY"), 'Downloaded content does not match expected content'
    end

    test 'should assert a file exists in bucket' do
      filename = 'cluster_example.txt'
      assert @client.bucket_file_exists?(@bucket_name, filename), 'Expected file does not exist in bucket'
      not_found = 'foot.txt'
      assert_not @client.bucket_file_exists?(@bucket_name, not_found), 'Unexpectedly found a file that should not exist'
    end

    test 'should copy a file to bucket' do
      existing_file = 'cluster_example.txt'
      filename = 'copied_cluster_example.txt'
      copied_file = @client.copy_bucket_file(@bucket_name, existing_file, filename)
      assert copied_file.is_a?(Google::Cloud::Storage::File), 'File copy failed'
      assert_equal filename, copied_file.name, 'Copied file name does not match expected name'
    end

    test 'should delete a file from bucket' do
      filename = 'cluster_example_2.txt'
      file_to_delete = File.open(Rails.root.join("test/test_data/#{filename}"))
      @client.create_bucket_file(@bucket_name, file_to_delete, filename)
      assert @client.bucket_file_exists?(@bucket_name, filename), 'File should exist before deletion'
      @client.delete_bucket_file(@bucket_name, filename)
      assert_not @client.bucket_file_exists?(@bucket_name, filename),
                 'File should not exist after deletion'
    end

    test 'should generate a signed URL for a file' do
      filename = 'cluster_example.txt'
      signed_url = @client.generate_signed_url(@bucket_name, filename)
      assert signed_url.present?, 'Signed URL generation failed'
      assert signed_url.start_with?("https://storage.googleapis.com/#{@bucket_name}/#{filename}"),
             'Signed URL does not match expected format'
    end

    test 'should generate API url for a file' do
      filename = 'cluster_example.txt'
      api_url = @client.generate_api_url(@bucket_name, filename)
      assert api_url.present?, 'API URL generation failed'
      assert_equal "https://www.googleapis.com/storage/v1/b/#{@bucket_name}/o/#{filename}",
                   api_url,
                   'API URL does not match expected format'
    end

    test 'should extract status code from error' do
      begin
        @client.get_bucket('does-not-exist')
      rescue Google::Cloud::PermissionDeniedError => e
        status_code = @client.extract_status_code(e)
        assert_equal 403, status_code, 'Extracted status code does not match expected value'
      end

      error = RuntimeError.new('An error occurred')
      status_code = @client.extract_status_code(error)
      assert_equal 500, status_code, 'Expected nil for non-Google API error'
    end
  end
end
