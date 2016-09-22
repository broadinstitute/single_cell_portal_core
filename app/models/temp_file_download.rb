class TempFileDownload
  include Mongoid::Document
  include Mongoid::Timestamps

  belongs_to :study_file

  field :token, type: String

  before_create :generate_token
  after_create :create_symbolic_link_and_schedule_cleanup
  before_destroy :remove_symbolic_link

  # symlink path to download, minus filename
  def download_path
    fullpath = self.study_file.upload.url.split('?').first.split('/')
    fullpath.pop
    fullpath << self.token
    newpath = fullpath.join('/')
    File.join(Rails.root, 'public', newpath)
  end

  # public path to file for browser
  def download_url
    File.join('/single_cell', 'data', self.study_file.url_safe_name, self.token, self.study_file.upload_file_name)
  end

  # source path of uploaded study_file
  def source_path
    self.study_file.upload.path
  end

  private

  # generate random hex string to make download urls unpredictable
  def generate_token
    self.token = SecureRandom.hex(32)
  end

  # create symbolic link, then schedule garbage collector using default timeout threshold to remove symlink
  # file will no longer be downloadable at given url
  def create_symbolic_link_and_schedule_cleanup
    FileUtils.mkdir_p self.download_path
    FileUtils.ln_s self.source_path, self.download_path + "/#{self.study_file.upload_file_name}"
    # schedule garbage collector to remove symlink
    TempFileDownloadCleanup.new(TempFileDownloadCleanup::DEFAULT_THRESHOLD).delay(run_at: (TempFileDownloadCleanup::DEFAULT_THRESHOLD.minutes + 5.seconds).from_now).perform
  end

  # removes symlink before record is deleted
  # first check if file still exists as study or file may have been deleted
  def remove_symbolic_link
    if !self.study_file.nil?
      FileUtils.rm_rf self.download_path
    end
  end
end
