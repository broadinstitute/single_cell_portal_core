class StudyFile
  include Mongoid::Document
  include Mongoid::Timestamps
  include Mongoid::Paperclip
  include Rails.application.routes.url_helpers

  # constants, used for statuses and file types
  STUDY_FILE_TYPES = ['Cluster Coordinates', 'Cluster Assignments', 'Expression Matrix', 'Gene List', 'Fastq', 'Documentation', 'Other']
  PARSEABLE_TYPES = ['Cluster Coordinates', 'Expression Matrix', 'Gene List']
  UPLOAD_STATUSES = %w(new uploading uploaded)
  PARSE_STATUSES = %w(unparsed parsing parsed)

  # associations
  belongs_to :study, index: true
  has_many :clusters, dependent: :destroy
  has_many :single_cells, dependent: :destroy
  has_many :cluster_points, dependent: :destroy
  has_many :expression_scores, dependent: :destroy
  has_many :precomputed_scores, dependent: :destroy
  has_many :temp_file_downloads

  # field definitions
  field :name, type: String
  field :path, type: String
  field :description, type: String
  field :file_type, type: String
  field :cluster_type, type: String
  field :url_safe_name, type: String
  field :status, type: String
  field :parse_status, type: String, default: 'unparsed'
  field :bytes_parsed, type: Integer, default: 0
  field :human_fastq_url, type: String
  field :human_data, type: Boolean, default: false

  # callbacks
  before_create   :make_data_dir
  before_create   :set_file_name_and_url_safe_name
  after_save      :check_public?
  before_destroy  :remove_public_symlink

  has_mongoid_attached_file :upload,
                            :path => ":rails_root/data/:url_safe_name/:filename",
                            :url => "/single_cell/data/:url_safe_name/:filename"

  # turning off validation to allow any kind of data file to be uploaded
  do_not_validate_attachment_file_type :upload

  # use custom content type validator for more control
  validate :check_upload_content_type

  Paperclip.interpolates :url_safe_name do |attachment, style|
    attachment.instance.url_safe_name
  end

  # return public url if study is public, otherwise redirect to create templink download url
  def download_path
    if self.upload_file_name.nil?
      self.human_fastq_url
    else
      if self.study.public?
        self.upload.url
      else
        download_private_file_path(self.study.url_safe_name, self.upload_file_name)
      end
    end
  end

  # JSON response for jQuery uploader
  def to_jq_upload
    {
        '_id' => self._id,
        'name' => read_attribute(:upload_file_name),
        'size' => read_attribute(:upload_file_size),
        'url' => download_path,
        'delete_url' => delete_study_file_study_path(self.study._id, self._id),
        'delete_type' => "DELETE"
    }
  end

  def parseable?
    PARSEABLE_TYPES.include?(self.file_type)
  end

  def parsed?
    self.parse_status == 'parsed'
  end

  # return an integer percentage of the parsing status
  def percent_parsed
    (self.bytes_parsed / self.upload_file_size.to_f * 100).floor
  end

  # file type as a css class
  def file_type_class
    self.file_type.downcase.split.join('-') + '-file'
  end

  # method to return number of lines in a file, uses built-in unix

  private

  def make_data_dir
    data_dir = Rails.root.join('data', self.study.url_safe_name)
    unless Dir.exist?(data_dir)
      FileUtils.mkdir_p(data_dir)
    end
  end

  # set filename and construct url safe name from study
  def set_file_name_and_url_safe_name
    if self.upload_file_name.nil?
      self.status = 'uploaded'
      if self.name.nil?
        self.name = ''
      end
    elsif (self.name.nil? || self.name.blank?) || (!self.new_record? && self.upload_file_name != self.name)
      self.name = self.upload_file_name
    end
    self.url_safe_name = self.study.url_safe_name
  end

  # add symlink if study is public
  def check_public?
    unless self.upload_file_name.nil?
      if self.study.public? && self.status == 'uploaded'
        FileUtils.ln_sf(self.upload.path, File.join(self.study.data_public_path, self.upload_file_name))
      end
    end
  end

  # clean up any symlinks before deleting a study file
  def remove_public_symlink
    unless self.upload_file_name.nil?
      if self.study.public?
        FileUtils.rm_f(File.join(self.study.data_public_path, self.upload_file_name))
      end
    end
  end

  # validate text/plain content type for parseable files
  def check_upload_content_type
    if self.parseable?
      if self.upload.content_type != 'text/plain'
        errors.add(:base, "Only text files are allowed for study files of type: '#{self.file_type}'")
      end
    end
  end
end
