require 'test_helper'

class UserAssetServiceTest < ActiveSupport::TestCase

  TEST_DATA_DIR = Rails.root.join('test', 'test_data', 'branding_groups')
  TEST_FILES = UserAssetService.get_directory_entries(TEST_DATA_DIR)

  # seed test data into public directory
  # will not overwrite existing data if there, but in that case the test for pulling remote data will fail
  # only intended for use in a CI environment
  def populate_test_data
    UserAssetService::ASSET_PATHS_BY_TYPE.values.each do |asset_path|
      unless Dir.exist?(asset_path)
        FileUtils.mkdir_p(asset_path)
      end
      entries = UserAssetService.get_directory_entries(asset_path)
      if entries.empty?
        TEST_FILES.each_with_index do |test_file, index|
          upload_dir = asset_path.join(index.to_s)
          FileUtils.mkdir_p(upload_dir)
          new_path = upload_dir.join(test_file)
          source_file = TEST_DATA_DIR.join(test_file)
          FileUtils.copy_file(source_file, new_path, preserve: true)
          FileUtils.chmod 'a+r', new_path
        end
      end
    end
  end

  # cache the current local state at the beginning of all test runs
  # can also "undo" the cached state to return the filesystem to its original state
  def cache_local_state(undo: false)
    cache_dir = "test-cache-#{SecureRandom.uuid}"
    if undo
      files = Dir.glob("#{Rails.root}/public/single_cell/test-cache-*/**/**").reject { |path| Dir.exist? path }
    else
      files = UserAssetService.get_local_assets
    end
    files.each do |pathname|
      pathname_parts = pathname.to_s.split('/')
      filename = pathname_parts.pop
      if undo
        folder = pathname_parts.reject { |dir| dir.starts_with? 'test-cache' }.join('/')
      else
        # insert cache dir under 'single_cell' dir
        single_cell_dir = pathname_parts.index('single_cell') + 1
        folder = pathname_parts.insert(single_cell_dir, cache_dir).join('/')
      end
      move_file(pathname, folder, filename)
    end
  end

  # move a file and clean up src copy, creating directories as needed
  def move_file(source, new_folder, filename)
    FileUtils.mkdir_p new_folder unless Dir.exist?(new_folder)
    destination = "#{new_folder}/#{filename}"
    FileUtils.mv source, destination
  end

  # clear the state of the remote UserAssetStorage bucket to ensure idempotency
  def clear_remote_bucket
    UserAssetService.get_remote_assets.map(&:delete)
  end

  # ensure directories are clear for each test to avoid issues w/ upstream/downstream tests
  before(:all) do
    clear_remote_bucket
    cache_local_state
    FileUtils.rm_rf Rails.root.join('public', 'single_cell', 'branding_groups')
    FileUtils.rm_rf Rails.root.join('public', 'single_cell', 'ckeditor_assets')
  end

  after(:all) do
    clear_remote_bucket
    FileUtils.rm_rf Rails.root.join('public', 'single_cell', 'branding_groups')
    FileUtils.rm_rf Rails.root.join('public', 'single_cell', 'ckeditor_assets')
    cache_local_state(undo: true)
    cache_dir = Dir.entries(Rails.root.join('public', 'single_cell')).detect { |dir| dir.starts_with? 'test-cache' }
    FileUtils.rm_rf Rails.root.join('public', 'single_cell', cache_dir) if cache_dir.present?
  end

  test 'should instantiate client' do
    storage_service = UserAssetService.storage_service
    assert storage_service.present?, 'Did not initialize storage service'
    # validate we're using the same service and not re-initializing every time
    new_service = UserAssetService.storage_service
    service_token = new_service.service.credentials.client.access_token
    issue_date = new_service.service.credentials.client.issued_at

    assert_equal UserAssetService.access_token, service_token
                 "Access tokens are not the same: #{UserAssetService.access_token} != #{service_token}"
    assert_equal UserAssetService.issued_at, issue_date,
                 "Creation timestamps are not the same: #{UserAssetService.issued_at} != #{issue_date}"
  end

  test 'should get storage bucket' do
    bucket = UserAssetService.get_storage_bucket
    assert bucket.present?, "Did not get storage bucket"
    assert_equal UserAssetService::STORAGE_BUCKET_NAME, bucket.name,
                 "Incorrect bucket returned; should have been #{UserAssetService::STORAGE_BUCKET_NAME} but found #{bucket.name}"
  end

  test 'should push and pull assets from remote' do
    # seed test data into directory so we have idempotent results
    populate_test_data
    local_assets = UserAssetService.get_local_assets
    assert_equal 9, local_assets.size,
                 "Did not find correct number of files, expected 9 but found #{local_assets.size}"
    filenames = local_assets.map {|asset| asset.basename.to_s}.uniq
    assert_equal TEST_FILES.sort, filenames.sort,
                 "Did not find correct files; expected #{TEST_FILES.sort} but found #{filenames.sort}"

    # do remote push
    pushed = UserAssetService.push_assets_to_remote
    assert pushed, "Did not successfully push assets to remote bucket"
    # gotcha for dealing with "cached" bucket state
    remote_assets = UserAssetService.get_remote_assets
    assert_equal 9, remote_assets.size,
                 "Did not find correct number of remote assets, expected 9 but found #{remote_assets.size}"

    # now remote local assets and pull from remote
    local_assets.each {|asset| File.delete(asset) }
    new_local_assets = UserAssetService.localize_assets_from_remote
    assert_equal local_assets.sort, new_local_assets.sort,
                 "Did not successfully localize remotes, #{new_local_assets.sort} != #{local_assets.sort}"
  end
end
