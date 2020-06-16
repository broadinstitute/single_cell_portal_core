##
# UserAssetService: manages uploading/localization of "user-provided" static asset files
# Used primarily for BrandingGroup images, but also supports legacy CKEditor uploads
##

class UserAssetService

  # GCP Compute project to run reads/writes in
  COMPUTE_PROJECT = ENV['GOOGLE_CLOUD_PROJECT'].blank? ? '' : ENV['GOOGLE_CLOUD_PROJECT']
  # Service account JSON credentials
  SERVICE_ACCOUNT_KEY = !ENV['SERVICE_ACCOUNT_KEY'].blank? ? File.absolute_path(ENV['SERVICE_ACCOUNT_KEY']) : ''

  # Asset Path helpers
  RAILS_PUBLIC_PATH = Rails.root.join('public', 'single_cell')
  ASSET_PATHS_BY_TYPE = {
      ckeditor_pictures: RAILS_PUBLIC_PATH.join('ckeditor_assets', 'pictures'),
      ckeditor_attachments: RAILS_PUBLIC_PATH.join('ckeditor_assets', 'attachments'),
      branding_images: RAILS_PUBLIC_PATH.join('branding_groups')
  }.with_indifferent_access
  ASSET_TYPES = ASSET_PATHS_BY_TYPE.keys.freeze

  # Bucket info; each Rails environment per project has a bucket
  STORAGE_BUCKET_NAME = "#{COMPUTE_PROJECT}-#{Rails.env}-asset-storage".freeze

  # initialize GCS driver with same credentials as FireCloudClient
  # will return existing instance after first call is made (does not re-instantiate)
  #
  # * *yields*
  #   - +Google::Cloud::Storage+
  def self.storage_service
    @@storage_service ||= Google::Cloud::Storage.new(keyfile: SERVICE_ACCOUNT_KEY)
  end

  # get storage driver access token
  #
  # * *return*
  #   - +String+ access token
  def self.access_token
    storage_service.service.credentials.client.access_token
  end

  # get storage driver issue timestamp
  #
  # * *return*
  #   - +DateTime+ issue timestamp
  def self.issued_at
    storage_service.service.credentials.client.issued_at
  end

  # get issuer of storage credentials
  #
  # * *return*
  #   - +String+ of issuer email
  def self.issuer
    storage_service.service.credentials.issuer
  end

  # getter for storage bucket where assets are stored long-term
  # if bucket is not found, it will create the bucket and return
  #
  # * *returns*
  #   - +Google::Cloud::Storage::Bucket+
  def self.get_storage_bucket
    storage_service.bucket(STORAGE_BUCKET_NAME) || storage_service.create_bucket(STORAGE_BUCKET_NAME)
  end

  # get all entries in a directory, ignoring hidden files
  #
  # * *params*
  #   - +pathname+ (Pathname, String) => Absolute or relative path to directory
  #
  # * *returns*
  #   - +Array<String>+ => Array of filenames
  def self.get_directory_entries(pathname = Dir.pwd)
    Dir.exists?(pathname) ? Dir.entries(pathname).keep_if {|entry| !entry.start_with?('.')} : []
  end
  
  # get a list of all local assets; can scope by asset type
  #
  # * *params*
  #   - +asset_type+ (String, Symbol) => type of asset as declared by ASSET_PATHS_BY_TYPE.keys
  #
  # * *returns*
  #   - +Array<Pathname>+ => Array of Pathname objects
  #
  # * *raises*
  #   - +TypeError+ => invalid asset type
  def self.get_local_assets(asset_type: nil)
    verify_asset_type(asset_type)
    local_files = []
    asset_paths = asset_type.present? ? [ASSET_PATHS_BY_TYPE[asset_type]] : ASSET_PATHS_BY_TYPE.values
    asset_paths.each do |asset_path|
      sub_dirs = get_directory_entries(asset_path)
      sub_dirs.each do |sub_dir|
        current_dir = asset_path.join(sub_dir)
        files = get_directory_entries(current_dir)
        local_files += files.map {|file| Pathname.new(current_dir).join(file)}
      end
    end
    local_files
  end

  # get a list of all local assets; can scope by asset type
  #
  # * *params*
  #   - +asset_type+ (String, Symbol) => type of asset as declared by ASSET_PATHS_BY_TYPE.keys
  #
  # * *returns*
  #   - +Google::Cloud::Storage::Bucket::List+ => Array of GCS File objects
  #
  # * *raises*
  #   - +TypeError+ => invalid asset type
  # get a list of remote assets; can scope by asset type
  def self.get_remote_assets(asset_type: nil)
    verify_asset_type(asset_type)
    bucket = get_storage_bucket
    # get prefix to filter remote assets by type, if specified
    asset_prefix = asset_type.present? ? get_remote_path(ASSET_PATHS_BY_TYPE[asset_type]) : nil
    bucket.files prefix: asset_prefix.to_s
  end

  # Push all local files to remote bucket storage; will overwrite any files in remote with current copy
  #
  # * *params*
  #   - +asset_type+ (String, Symbol) => Type of assets to push; defaults to all
  #
  # * *returns*
  #   - +TrueClass+ => true upon completion
  #
  # * *raises*
  #   - +TypeError+ => Invalid asset type
  #   - +ArgumentError+ => Invalid path to local file
  #   - +Google::Cloud::Error+ => Error pushing file to bucket
  def self.push_assets_to_remote(asset_type: nil)
    verify_asset_type(asset_type)
    bucket = get_storage_bucket
    get_local_assets(asset_type: asset_type).each do |asset_path|
      remote_path = get_remote_path(asset_path)
      bucket.create_file asset_path.to_s, remote_path
    end
    true
  end

  # convert a local path into a remote path for a file in a bucket (removes RAILS_PUBLIC_PATH prefix)
  #
  # * *params*
  #   - +pathname+ (Pathname) => Pathname of local file
  #
  # * *returns*
  #   - +String+ => String representation of remote filepath
  def self.get_remote_path(pathname)
    remote_path = pathname.to_s.split(RAILS_PUBLIC_PATH.to_s).last
    remote_path.slice!(0, 1) # trim off leading /
    remote_path.to_s
  end

  # pull down all assets from remote storage; will skip any files that already exist
  # * *params*
  #   - +asset_type+ (String, Symbol) => Type of assets to push; defaults to all
  #
  # * *returns*
  #   - +Array<Pathname>+ => Array of Pathnames pointing at files that were localized
  #
  # * *raises*
  #   - +TypeError+ => Invalid asset type
  #   - +Google::Cloud::Error+ => Error retrieving file from bucket
  def self.localize_assets_from_remote(asset_type: nil)
    verify_asset_type(asset_type)
    localized_files = []
    get_remote_assets(asset_type: asset_type).each do |remote_asset|
      local_path = get_local_path(remote_asset.name)
      unless File.exist?(local_path)
        # we need to first make the directory where the file will go, otherwise this will throw an error
        create_download_directory(remote_asset.name)
        remote_asset.download local_path
        # make sure file is readable by all, writable only by owner
        FileUtils.chmod 644, local_path
        localized_files << Pathname.new(local_path)
      end
    end
    localized_files
  end

  # convert a remote path into a local path for a file to be localized from a bucket (prepends RAILS_PUBLIC_PATH prefix)
  #
  # * *params*
  #   - +pathname+ (Pathname) => Pathname of remote file
  #
  # * *returns*
  #   - +String+ => String representation of local filepath
  def self.get_local_path(pathname)
    RAILS_PUBLIC_PATH.join(pathname).to_s
  end

  # create a local directory in which to localize a remote asset to prevent Errno::ENOENT errors
  # * *params*
  #   - +pathname+ (Pathname) => Pathname of remote file
  #
  # * *returns*
  #   - +Pathname+ => Pathname of local directory
  def self.create_download_directory(pathname)
    parent_dir = Pathname.new(pathname).parent
    fullpath = RAILS_PUBLIC_PATH.join(parent_dir)
    FileUtils.mkdir_p(fullpath) unless Dir.exists?(fullpath)
    fullpath
  end

  private

  # verify type of requested asset is valid
  #
  # * *params*
  #   - +asset_type+ (String, Symbol) => type of asset as declared by ASSET_PATHS_BY_TYPE.keys
  #
  # * *raises*
  #   - +TypeError+ => invalid asset type
  def self.verify_asset_type(asset_type)
    if asset_type.present? && !ASSET_TYPES.include?(asset_type.to_s)
      raise TypeError.new("#{asset_type} is not a registered asset type: #{ASSET_TYPES.join(', ')}")
    end
  end
end
