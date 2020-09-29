class StudyFile

  ###
  #
  # StudyFile: class holding metadata about data files either uploaded through the UI or 'synced' from a GCS bucket
  #
  ###

  ###
  #
  # SETTINGS & FIELD DEFINITIONS
  #
  ###

  include Mongoid::Document
  include Mongoid::Timestamps
  include Mongoid::Paperclip
  include Rails.application.routes.url_helpers # for accessing download_file_path and download_private_file_path
  include Swagger::Blocks

  # constants, used for statuses and file types
  STUDY_FILE_TYPES = ['Cluster', 'Coordinate Labels' ,'Expression Matrix', 'MM Coordinate Matrix', '10X Genes File',
                      '10X Barcodes File', 'Gene List', 'Metadata', 'Fastq', 'BAM', 'BAM Index', 'Documentation',
                      'Other', 'Analysis Output', 'Ideogram Annotations']
  PARSEABLE_TYPES = ['Cluster', 'Coordinate Labels', 'Expression Matrix', 'MM Coordinate Matrix', '10X Genes File',
                     '10X Barcodes File', 'Gene List', 'Metadata', 'Analysis Output']
  DISALLOWED_SYNC_TYPES = ['Fastq']
  UPLOAD_STATUSES = %w(new uploading uploaded)
  PARSE_STATUSES = %w(unparsed parsing parsed failed)
  PRIMARY_DATA_EXTENTIONS = %w(fastq fastq.zip fastq.gz fastq.tar.gz fq fq.zip fq.gz fq.tar.gz bam bam.gz bam.bai bam.gz.bai)
  PRIMARY_DATA_TYPES = ['Fastq', 'BAM', 'BAM Index']
  TAXON_REQUIRED_TYPES = ['Fastq', 'BAM', 'Expression Matrix', 'MM Coordinate Matrix', 'Ideogram Annotations']
  ASSEMBLY_REQUIRED_TYPES = ['BAM', 'Ideogram Annotations']
  GZIP_MAGIC_NUMBER = "\x1f\x8b".force_encoding(Encoding::ASCII_8BIT)
  REQUIRED_ATTRIBUTES = %w(file_type name)
  BULK_DOWNLOAD_TYPES = ['Expression', 'Metadata', 'Cluster', 'Coordinate Labels', 'Fastq', 'BAM', 'Documentation',
                         'Other', 'Analysis Output', 'Ideogram Annotations']

  # Constants for scoping values for AnalysisParameter inputs/outputs
  ASSOCIATED_MODEL_METHOD = %w(gs_url name upload_file_name bucket_location)
  ASSOCIATED_MODEL_DISPLAY_METHOD = %w(name upload_file_name bucket_location)
  OUTPUT_ASSOCIATION_ATTRIBUTE = %w(taxon_id genome_assembly_id study_file_bundle_id)
  ANALYSIS_PARAMETER_FILTERS = {
      'file_type' => STUDY_FILE_TYPES.dup,
      'taxon_id' => Taxon.all.map {|t| [t.common_name, t.id.to_s]}
  }

  # associations
  belongs_to :study, index: true
  has_many :cluster_groups, dependent: :destroy
  has_many :genes, dependent: :destroy
  has_many :precomputed_scores, dependent: :destroy
  has_many :cell_metadata, dependent: :destroy
  belongs_to :taxon, optional: true
  belongs_to :genome_assembly, optional: true
  belongs_to :study_file_bundle, optional: true

  # field definitions
  field :name, type: String
  field :description, type: String
  field :file_type, type: String
  field :status, type: String
  field :parse_status, type: String, default: 'unparsed'
  field :data_dir, type: String
  field :human_fastq_url, type: String
  field :human_data, type: Boolean, default: false
  field :use_metadata_convention, type: Boolean, default: false
  field :generation, type: String
  field :x_axis_label, type: String, default: ''
  field :y_axis_label, type: String, default: ''
  field :z_axis_label, type: String, default: ''
  field :x_axis_min, type: Integer
  field :x_axis_max, type: Integer
  field :y_axis_min, type: Integer
  field :y_axis_max, type: Integer
  field :z_axis_min, type: Integer
  field :z_axis_max, type: Integer
  field :queued_for_deletion, type: Boolean, default: false
  field :remote_location, type: String, default: ''
  field :options, type: Hash, default: {}

  Paperclip.interpolates :data_dir do |attachment, style|
    attachment.instance.data_dir
  end

  ##
  #
  # SWAGGER DEFINITIONS
  #
  ##

  swagger_schema :StudyFile do
    key :required, [:file_type, :name]
    key :name, 'StudyFile'
    property :id do
      key :type, :string
    end
    property :study_id do
      key :type, :string
      key :description, 'ID of Study to which StudyFile belongs'
    end
    property :taxon_id do
      key :type, :string
      key :description, 'Database ID of Taxon entry (species) to which StudyFile belongs, if required/present.  THIS IS NOT THE NCBI TAXON ID.'
    end
    property :species do
      key :type, :string
      key :description, '(optional) Common name of a species registered in the portal to set taxon_id association manually'
    end
    property :genome_assembly_id do
      key :type, :string
      key :description, 'ID of GenomeAssembly to which StudyFile belongs, if required/present'
    end
    property :assembly do
      key :type, :string
      key :description, '(optional) Common name of a genome assembly registered in the portal to set genome_assembly_id association manually'
    end
    property :study_file_bundle_id do
      key :type, :string
      key :description, 'ID of StudyFileBundle to which StudyFile belongs, if present'
    end
    property :name do
      key :type, :string
      key :description, 'Name of StudyFile (either filename or name of Cluster/Gene List)'
    end
    property :description do
      key :type, :string
      key :description, 'StudyFile description, used in download views'
    end
    property :upload do
      key :type, :string
      key :format, :binary
      key :description, 'File object that StudyFile represents (will auto-set all upload_* attributes from File headers)'
    end
    property :upload_file_name do
      key :type, :string
      key :description, 'Filename of upload File object'
    end
    property :upload_content_type do
      key :type, :string
      key :description, 'Content-Type of upload File object'
    end
    property :upload_file_size do
      key :type, :integer
      key :description, 'Size (in bytes) of upload File object'
    end
    property :upload_fingerprint do
      key :type, :string
      key :description, 'Checksum of upload File object'
    end
    property :upload_updated_at do
      key :type, :string
      key :format, :date_time
      key :description, 'Last update timestamp of upload File object'
    end
    property :file_type do
      key :type, :string
      key :enum, STUDY_FILE_TYPES
      key :description, 'Type of file, governs parsing/caching behavior'
    end
    property :status do
      key :type, :string
      key :enum, UPLOAD_STATUSES
      key :description, 'Status of File object upload (new, uploading, or uploaded)'
    end
    property :parse_status do
      key :type, :string
      key :enum, PARSE_STATUSES
      key :description, 'Parse status of StudyFile (unparsed, parsing, or parsed)'
    end
    property :data_dir do
      key :type, :string
      key :description, 'Local directory where File object is localized to (for parsing)'
    end
    property :remote_location do
      key :type, :string
      key :description, 'Location in GCS bucket of File object'
    end
    property :human_fastq_url do
      key :type, :string
      key :format, :url
      key :description, 'External URL for human sequence data (if required)'
    end
    property :human_data do
      key :type, :boolean
      key :default, false
      key :description, 'Boolean indication whether StudyFile represents human data'
    end
    property :use_metadata_convention do
      key :type, :boolean
      key :default, false
      key :description, 'Boolean indication whether StudyFile uses the metadata convention'
    end
    property :generation do
      key :type, :string
      key :description, 'GCS generation tag of File in bucket'
    end
    property :x_axis_label do
      key :type, :string
      key :description, 'Label to use on X axis of plots (for Clusters)'
    end
    property :y_axis_label do
      key :type, :string
      key :description, 'Label to use on Y axis of plots (for Clusters, Expression Matrix, MM Coordinate Matrix)'
    end
    property :z_axis_label do
      key :type, :string
      key :description, 'Label to use on Z axis of plots (for Clusters)'
    end
    property :x_axis_min do
      key :type, :integer
      key :description, 'X axis domain minimum (for Clusters)'
    end
    property :x_axis_max do
      key :type, :integer
      key :description, 'X axis domain maximum (for Clusters)'
    end
    property :y_axis_min do
      key :type, :integer
      key :description, 'Y axis domain minimum (for Clusters)'
    end
    property :y_axis_max do
      key :type, :integer
      key :description, 'Y axis domain maximum (for Clusters)'
    end
    property :z_axis_min do
      key :type, :integer
      key :description, 'Z axis domain minimum (for Clusters)'
    end
    property :z_axis_max do
      key :type, :integer
      key :description, 'Z axis domain maximum (for Clusters)'
    end
    property :queued_for_deletion do
      key :type, :boolean
      key :default, false
      key :description, 'Boolean indication whether file is queued for garbage collection'
    end
    property :options do
      key :type, :object
      key :default, {}
      key :description, 'Key/Value storage of extra file options'
    end
    property :created_at do
      key :type, :string
      key :format, :date_time
      key :description, 'Creation timestamp'
    end
    property :updated_at do
      key :type, :string
      key :format, :date_time
      key :description, 'Last update timestamp'
    end
  end

  swagger_schema :StudyFileInput do
    allOf do
      schema do
        property :taxon_id do
          key :type, :string
          key :description, 'Database ID of Taxon entry (species) to which StudyFile belongs, if required/present.  THIS IS NOT THE NCBI TAXON ID.'
        end
        property :species do
          key :type, :string
          key :description, '(optional) Common name of a species registered in the portal to set taxon_id association manually'
        end
        property :genome_assembly_id do
          key :type, :string
          key :description, 'ID of GenomeAssembly to which StudyFile belongs, if required/present'
        end
        property :assembly do
          key :type, :string
          key :description, '(optional) Common name of a genome assembly registered in the portal to set genome_assembly_id association manually'
        end
        property :study_file_bundle_id do
          key :type, :string
          key :description, 'ID of StudyFileBundle to which StudyFile belongs, if present'
        end
        property :name do
          key :type, :string
          key :description, 'Name of StudyFile (either filename or name of Cluster/Gene List)'
        end
        property :description do
          key :type, :string
          key :description, 'StudyFile description, used in download views'
        end
        property :file_type do
          key :type, :string
          key :enum, STUDY_FILE_TYPES
          key :description, 'Type of file, governs parsing/caching behavior'
        end
        property :status do
          key :type, :string
          key :enum, UPLOAD_STATUSES
          key :description, 'Status of File object upload (new, uploading, or uploaded)'
        end
        property :remote_location do
          key :type, :string
          key :description, 'Location in GCS bucket of File object'
        end
        property :human_fastq_url do
          key :type, :string
          key :format, :url
          key :description, 'External URL for human sequence data (if required)'
        end
        property :human_data do
          key :type, :boolean
          key :default, false
          key :description, 'Boolean indication whether StudyFile represents human data'
        end
        property :use_metadata_convention do
          key :type, :boolean
          key :default, false
          key :description, 'Boolean indication whether StudyFile uses the metadata convention'
        end
        property :generation do
          key :type, :string
          key :description, 'GCS generation tag of File in bucket'
        end
        property :x_axis_label do
          key :type, :string
          key :description, 'Label to use on X axis of plots (for Clusters)'
        end
        property :y_axis_label do
          key :type, :string
          key :description, 'Label to use on Y axis of plots (for Clusters, Expression Matrix, MM Coordinate Matrix)'
        end
        property :z_axis_label do
          key :type, :string
          key :description, 'Label to use on Z axis of plots (for Clusters)'
        end
        property :x_axis_min do
          key :type, :integer
          key :description, 'X axis domain minimum (for Clusters)'
        end
        property :x_axis_max do
          key :type, :integer
          key :description, 'X axis domain maximum (for Clusters)'
        end
        property :y_axis_min do
          key :type, :integer
          key :description, 'Y axis domain minimum (for Clusters)'
        end
        property :y_axis_max do
          key :type, :integer
          key :description, 'Y axis domain maximum (for Clusters)'
        end
        property :z_axis_min do
          key :type, :integer
          key :description, 'Z axis domain minimum (for Clusters)'
        end
        property :z_axis_max do
          key :type, :integer
          key :description, 'Z axis domain maximum (for Clusters)'
        end
        property :options do
          key :type, :object
          key :default, {}
          key :description, 'Key/Value storage of extra file options'
        end
      end
    end
  end

  swagger_schema :StudyFileSync do
    allOf do
      schema do
        property :taxon_id do
          key :type, :string
          key :description, 'Database ID of Taxon entry (species) to which StudyFile belongs, if required/present.  THIS IS NOT THE NCBI TAXON ID.'
        end
        property :species do
          key :type, :string
          key :description, '(optional) Common name of a species registered in the portal to set taxon_id association manually'
        end
        property :genome_assembly_id do
          key :type, :string
          key :description, 'ID of GenomeAssembly to which StudyFile belongs, if required/present'
        end
        property :assembly do
          key :type, :string
          key :description, '(optional) Common name of a genome assembly registered in the portal to set genome_assembly_id association manually'
        end
        property :name do
          key :type, :string
          key :description, 'Name of StudyFile (either filename or name of Cluster/Gene List)'
        end
        property :description do
          key :type, :string
          key :description, 'StudyFile description, used in download views'
        end
        property :file_type do
          key :type, :string
          key :enum, STUDY_FILE_TYPES
          key :description, 'Type of file, governs parsing/caching behavior'
        end
        property :remote_location do
          key :type, :string
          key :description, 'Location in GCS bucket of File object'
        end
        property :human_data do
          key :type, :boolean
          key :default, false
          key :description, 'Boolean indication whether StudyFile represents human data'
        end
        property :use_metadata_convention do
          key :type, :boolean
          key :default, false
          key :description, 'Boolean indication whether StudyFile uses the metadata convention'
        end
        property :generation do
          key :type, :string
          key :description, 'GCS generation tag of File in bucket'
        end
        property :options do
          key :type, :object
          key :default, {}
          key :description, 'Key/Value storage of extra file options'
        end
      end
    end
  end

  swagger_schema :SiteStudyFile do
    key :name, 'StudyFile'
    property :name do
      key :type, :string
      key :description, 'Name of StudyFile (either filename or name of Cluster/Gene List)'
    end
    property :description do
      key :type, :string
      key :description, 'StudyFile description, used in download views'
    end
    property :upload_content_type do
      key :type, :string
      key :description, 'Content-Type of upload File object'
    end
    property :upload_file_size do
      key :type, :integer
      key :description, 'Size (in bytes) of upload File object'
    end
    property :file_type do
      key :type, :string
      key :enum, StudyFile::STUDY_FILE_TYPES
      key :description, 'Type of file, governs parsing/caching behavior'
    end
    property :bucket_location do
      key :type, :string
      key :description, 'Location in GCS bucket of File object'
    end
    property :download_url do
      key :type, :string
      key :description, 'URL to download file'
    end
    property :media_url do
      key :type, :string
      key :description, 'URL to stream file to client'
    end
  end

  swagger_schema :FileBundleInput do
    allOf do
      schema do
        property :name do
          key :type, :string
          key :description, 'Filename of File object'
        end
        property :file_type do
          key :type, :string
          key :enum, STUDY_FILE_TYPES
          key :description, 'File type of File object'
        end
      end
    end
  end

  ###
  #
  # VALIDATIONS & CALLBACKS
  #
  ###

  # callbacks
  before_validation   :set_file_name_and_data_dir, on: :create
  before_save         :sanitize_name
  after_save          :set_cluster_group_ranges, :set_options_by_file_type

  has_mongoid_attached_file :upload,
                            :path => ":rails_root/data/:data_dir/:id/:filename",
                            :url => ''

  # turning off validation to allow any kind of data file to be uploaded
  do_not_validate_attachment_file_type :upload

  validates_uniqueness_of :upload_file_name, scope: :study_id, unless: Proc.new {|f| f.human_data?}
  validates_presence_of :name
  validates_presence_of :human_fastq_url, if: proc {|f| f.human_data}
  validates_format_of :human_fastq_url, with: URI.regexp,
                      message: 'is not a valid URL', if: proc {|f| f.human_data}
  validate :validate_name_by_file_type

  validates_format_of :description, with: ValidationTools::NO_SCRIPT_TAGS,
                      message: ValidationTools::NO_SCRIPT_TAGS_ERROR, allow_blank: true

  validates_format_of :x_axis_label, with: ValidationTools::NO_SCRIPT_TAGS,
                      message: ValidationTools::NO_SCRIPT_TAGS_ERROR,
                      allow_blank: true
  validates_format_of :y_axis_label, with: ValidationTools::NO_SCRIPT_TAGS,
                      message: ValidationTools::NO_SCRIPT_TAGS_ERROR,
                      allow_blank: true
  validates_format_of :z_axis_label, with: ValidationTools::NO_SCRIPT_TAGS,
                      message: ValidationTools::NO_SCRIPT_TAGS_ERROR,
                      allow_blank: true

  validates_format_of :generation, with: /\A\d+\z/, if: proc {|f| f.generation.present?}

  validates_inclusion_of :file_type, in: STUDY_FILE_TYPES, unless: proc {|f| f.file_type == 'DELETE'}

  validate :check_taxon, on: :create
  validate :check_assembly, on: :create
  validate :ensure_metadata_singleton, if: proc {|f| f.file_type == 'Metadata'}

  ###
  #
  # INSTANCE METHODS
  #
  ###

  # return correct path to file based on visibility & type
  def download_path
    if self.upload_file_name.nil?
      self.human_fastq_url
    else
      if self.study.public?
        download_file_path(accession: self.study.accession, study_name: self.study.url_safe_name, filename: self.bucket_location)
      else
        download_private_file_path(accession: self.study.accession, study_name: self.study.url_safe_name, filename: self.bucket_location)
      end
    end
  end

  # JSON response for jQuery uploader
  def to_jq_upload(error=nil)
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

  def parsing?
    self.parse_status == 'parsing'
  end

  # determine whether we have all necessary files to parse this file.  Mainly applies to MM Coordinate Matrices and associated 10X files
  def able_to_parse?
    if !self.parseable?
      false
    else
      case self.file_type
      when 'MM Coordinate Matrix'
        self.study_file_bundle.present? && self.study_file_bundle.completed?
      when '10X Genes File'
        self.study_file_bundle.present? && self.study_file_bundle.completed?
      when '10X Barcodes File'
        self.study_file_bundle.present? && self.study_file_bundle.completed?
      else
        true # the file is parseable and a singleton
      end
    end
  end

  # file type as a css class
  def file_type_class
    self.file_type.downcase.split.join('-') + '-file'
  end

  # generate a gs-url to this study file in the study's GCS bucket
  def gs_url
    "gs://#{self.study.bucket_id}/#{self.bucket_location}"
  end

  def api_url
    api_url = Study.firecloud_client.execute_gcloud_method(:generate_api_url, 0, self.study.bucket_id, self.bucket_location)
    api_url + '?alt=media'
  end

  # determine if a file has been uploaded
  def uploaded?
    if self.human_data?
      true # human sequence data is remote, so this is always true
    else
      self.generation.present? || self.status == 'uploaded'
    end
  end

  # convert all domain ranges from floats to integers
  def convert_all_ranges
    if self.file_type == 'Cluster'
      required_vals = 4
      domain = {
          x_axis_min: self.x_axis_min.to_i == 0 ? nil : self.x_axis_min.to_i,
          x_axis_max: self.x_axis_max.to_i == 0 ? nil : self.x_axis_max.to_i,
          y_axis_min: self.y_axis_min.to_i == 0 ? nil : self.y_axis_min.to_i,
          y_axis_max: self.y_axis_max.to_i == 0 ? nil : self.y_axis_max.to_i
      }
      empty_domain = {
          x_axis_min: nil,
          x_axis_max: nil,
          y_axis_min: nil,
          y_axis_max: nil
      }
      if self.cluster_groups.first.is_3d?
        domain[:z_axis_min] = self.z_axis_min.to_i == 0 ? nil : self.z_axis_min.to_i
        domain[:z_axis_max] = self.z_axis_max.to_i == 0 ? nil : self.z_axis_max.to_i
        empty_domain[:z_axis_min] = nil
        empty_domain[:z_axis_max] = nil
        required_vals = 6
      end
      # need to clear out domain first to force persistence
      self.update(empty_domain)
      if required_vals == domain.values.compact.size
        self.update(domain)
      end
    end
  end

  # end path for a file when localizing during a parse
  def download_location
    self.remote_location.blank? ? File.join(self.id, self.upload_file_name) : self.remote_location
  end

  # for constructing a path to a file in a Google bucket
  def bucket_location
    self.remote_location.blank? ? self.upload_file_name : self.remote_location
  end

  def local_location
    path = Rails.root.join(self.study.data_store_path, self.download_location)
    if File.exists?(path)
      path
    else
      path = Rails.root.join(self.study.data_store_path, self.bucket_location)
      File.exists?(path) ? path : nil
    end
  end

  # generate a download path to use with bulk_download
  # takes the form of :study_accession/:output_directory_name/:filename
  def bulk_download_pathname
    "#{self.study.accession}/#{self.output_directory_name}/#{self.upload_file_name}"
  end

  # Map of StudyFile#file_type to ::BULK_DOWNLOAD_TYPES, maintaining relationship for bundled files to parent
  def bulk_download_type
    # put bundled files in a sub-directory named after the bundle parent's ID so relationship is maintained
    # make sure bundle_parent is a StudyFile (can be ClusterGroup for coordinate label files)
    if self.is_bundled? && self.bundle_parent.is_a?(StudyFile)
      bp = self.bundle_parent
      "#{bp.simplified_file_type}/#{bp.id}"
    else
      self.simplified_file_type
    end
  end

  # lump MM Coordinate Matrices & dense expression matrices together for convenience in bulk download
  def simplified_file_type
    case self.file_type
    when /Matrix/
      'Expression'
    else
      self.file_type
    end
  end

  # retrieve a directory name based on file_type
  # bundled files travel with the parent, using their parent's directory
  # dense (Expression Matrix) and sparse (MM Coordinate Matrix) are lumped together
  def output_directory_name
    self.bulk_download_type.downcase.gsub(/\s/, '_')
  end

  def is_local?
    self.local_location.present?
  end

  def is_bundled?
    self.study_file_bundle.present?
  end

  # get any 'bundled' files that correspond to this file
  def bundled_files
    if self.study_file_bundle.present?
      self.study_file_bundle.bundled_files
    else
      # base 'selector' for query, used to search study_file.options hash
      selector = 'options'
      query_id = self.id.to_s
      case self.file_type
      when 'MM Coordinate Matrix'
        selector += '.matrix_id'
      when 'BAM'
        selector += '.bam_id'
      when 'Cluster'
        selector += '.cluster_group_id'
        query_id = self.cluster_groups.first.id.to_s
      end
      StudyFile.where(selector => query_id) # return Mongoid::Criteria to lazy-load, better performance
    end
  end

  # get the bundle 'parent' file for a bundled file (e.g. MM Coordinate Matrix that is bundled with a 10X Genes File)
  # inverse of study_file.bundled_files.  In the case of Coordinate Labels, this returns the cluster, not the file
  def bundle_parent
    if self.study_file_bundle.present?
      self.study_file_bundle.bundle_target
    else
      model = StudyFile
      case self.file_type
      when /10X/
        selector = :matrix_id
      when 'BAM Index'
        selector = :bam_id
      when 'Coordinate Labels'
        selector = :cluster_group_id
        model = ClusterGroup
      end
      # call find_by(id: ) to avoid Mongoid::Errors::InvalidFind
      model.find_by(id: self.options[selector])
    end
  end

  # determine if this file is a bundle parent
  def is_bundle_parent?
    if self.study_file_bundle.present?
      self.study_file_bundle.parent == self
    else
      false
    end
  end

  # retrieve the cluster group id from the options hash for a cluster labels file
  def coordinate_labels_font_family
    if self.options[:font_family].blank?
      'Helvetica Neue'
    else
      self.options[:font_family]
    end
  end

  # retrieve the font size from the options hash for a cluster labels file
  def coordinate_labels_font_size
    if self.options[:font_size].blank?
      10
    else
      self.options[:font_size]
    end
  end

  # retrieve the font color from the options hash for a cluster labels file
  def coordinate_labels_font_color
    if self.options[:font_color].blank?
      '#333333'
    else
      self.options[:font_color]
    end
  end

  # determine a file's content type by reading the first 2 bytes and comparing to known magic numbers
  def determine_content_type
    location = File.join(self.study.data_store_path, self.download_location)
    if !File.exists?(location)
      location = File.join(self.study.data_store_path, self.bucket_location)
    end
    signature = File.open(location).read(2)
    if signature == StudyFile::GZIP_MAGIC_NUMBER
      'application/gzip'
    else
      'text/plain'
    end
  end

  # helper method for retrieving species common name
  def species_name
    self.taxon.present? ? self.taxon.common_name : nil
  end

  # helper to return assembly name
  def genome_assembly_name
    self.genome_assembly.present? ? self.genome_assembly.name : nil
  end

  # helper to return annotation, if present
  def genome_annotation
    self.genome_assembly.present? ? self.genome_assembly.current_annotation : nil
  end

  # helper to return public link to genome annotation, if present
  def genome_annotation_link
    if self.genome_assembly.present? && self.genome_assembly.current_annotation.present?
      self.genome_assembly.current_annotation.public_annotation_link
    else
      nil
    end
  end

  # helper to return public link to genome annotation index, if present
  def genome_annotation_index_link
    if self.genome_assembly.present? && self.genome_assembly.current_annotation.present?
      self.genome_assembly.current_annotation.public_annotation_index_link
    else
      nil
    end
  end

  ###
  #
  # CACHING METHODS
  #
  ###

  # helper method to invalidate any matching front-end caches when parsing/deleting a study_file
  def invalidate_cache_by_file_type
    cache_key = self.cache_removal_key
    unless cache_key.nil?
      # clear matching caches in background
      CacheRemovalJob.new(cache_key).delay(queue: :cache).perform
    end
  end

  # helper method to return cache removal key based on file type (this is refactored out for use in tests)
  def cache_removal_key
    study_name = self.study.url_safe_name
    accession = self.study.accession
    case self.file_type
      when 'Cluster'
        @cache_key = "#{accession}/#{study_name}.*render_cluster"
      when 'Coordinate Labels'
        @cache_key = "#{accession}/#{study_name}.*render_cluster"
      when 'Expression Matrix'
        @cache_key = "#{accession}/#{study_name}.*expression"
      when 'MM Coordinate Matrix'
        @cache_key = "#{accession}/#{study_name}.*expression"
      when /10X.*File/
        @cache_key = "#{accession}/#{study_name}.*expression"
      when 'Gene List'
        @cache_key = "#{accession}/#{study_name}.*precomputed_gene_expression"
      when 'Metadata'
        # when reparsing metadata, almost all caches now become invalid so we just clear all matching the study
        @cache_key =  "#{accession}/#{study_name}"
      when 'Ideogram Annotations'
        @cache_key = "#{accession}/#{study_name}.*render_cluster"
      else
        @cache_key = nil
    end
    @cache_key
  end

  ###
  #
  # DELETE METHODS
  #
  ###

  # delete all queued study file objects
  def self.delete_queued_files
    study_files = self.where(queued_for_deletion: true)
    study_files.each do |file|
      Rails.logger.info "#{Time.zone.now} deleting queued file #{file.name} in study #{file.study.name}."
      file.destroy
      Rails.logger.info "#{Time.zone.now} #{file.name} successfully deleted."
    end
    true
  end

  # remove a local copy on the file system if a parse fails
  def remove_local_copy
    Rails.logger.info "Removing local copy of #{self.upload_file_name}"
    Dir.chdir(self.study.data_store_path)
    if Dir.exists?(self.id.to_s)
      Rails.logger.info "Removing upload directory for #{self.upload_file_name} at #{Dir.pwd}/#{self.id.to_s}"
      FileUtils.rm_rf(self.id.to_s)
    elsif File.exists?(self.bucket_location)
      Rails.logger.info "Removing local copy at #{Dir.pwd}/#{self.bucket_location}"
      File.delete(self.bucket_location)
    end
    Rails.logger.info "Removal of local copy of #{self.upload_file_name} complete"
  end

  # check if this file can be deleted "safely"; e.g. not being used in any running parse jobs
  # most files just need to check if they are still parsing; cluster/metadata files need to check for subsampling
  def can_delete_safely?
    if self.parsing?
      false
    else
      case self.file_type
      when 'Metadata'
        !self.study.cluster_groups.where(is_subsampling: true).any?
      when 'Cluster'
        cluster = ClusterGroup.find_by(study_file_id: self.id)
        cluster.present? && !cluster.is_subsampling?
      else
        true
      end
    end
  end

  ##
  #
  # MISC METHODS
  #
  ##

  # get the name of form partial for the wizard uploader by file type
  def wizard_partial_name
    case self.file_type
    when 'Cluster'
      'initialize_ordinations_form'
    when 'Coordinate Labels'
      'initialize_labels_form'
    when 'Expression Matrix'
      'initialize_expression_form'
    when 'MM Coordinate Matrix'
      'initialize_expression_form'
    when '10X Genes File'
      'initialize_expression_form'
    when '10X Barcodes File'
      'initialize_expression_form'
    when 'Expression Matrix'
      'initialize_expression_form'
    when 'Metadata'
      'initialize_metadata_form'
    when 'Fastq'
      'initialize_primary_data_form'
    when 'BAM'
      'initialize_primary_data_form'
    when 'BAM Index'
      'initialize_primary_data_form'
    when 'Gene List'
      'initialize_marker_genes_form'
    else
      'initialize_misc_form'
    end
  end

  # get the ID of form for the wizard uploader by file type
  def wizard_form_id
    case self.file_type
    when 'Cluster'
      "ordinations_form_#{self.id}"
    when 'Coordinate Labels'
      "labels_form_#{self.id}"
    when 'Expression Matrix'
      "expression_form_#{self.id}"
    when 'MM Coordinate Matrix'
      "expression_form_#{self.id}"
    when '10X Genes File'
      "bundled_file_form_#{self.id}"
    when '10X Barcodes File'
      "bundled_file_form_#{self.id}"
    when 'Expression Matrix'
      "misc_form_#{self.id}"
    when 'Metadata'
      "metadata_form"
    when 'Fastq'
      "primary_data_form_#{self.id}"
    when 'BAM'
      "primary_data_form_#{self.id}"
    when 'BAM Index'
      "bundled_file_form_#{self.id}"
    when 'Gene List'
      "marker_genes_form_#{self.id}"
    else
      "misc_form_#{self.id}"
    end
  end

  # DOM ID of the parent div holding the form for this file, used in upload wizard and sync page
  def form_container_id
    "container-#{self.id}"
  end

  # DOM ID for use in Selenium for accessing difference elements
  def name_as_id
    self.upload_file_name.gsub(/\./, '_')
  end

  def generate_expression_matrix_cells
    begin
      study = self.study
      existing_array = DataArray.where(name: "#{self.name} Cells", array_type: 'cells', linear_data_type: 'Study',
                                       linear_data_id: self.study_id).any?
      unless existing_array
        remote = Study.firecloud_client.execute_gcloud_method(:get_workspace_file, 0, study.bucket_id, self.bucket_location)
        if remote.present?
          study.make_data_dir
          download_location = study.data_store_path
          if self.remote_location.blank?
            download_location = File.join(study.data_store_path, self.id)
            Dir.mkdir download_location
          elsif self.remote_location.include?('/')
            subdir = self.remote_location.split('/').first
            download_location = File.join(study.data_store_path, subdir)
          end
          msg = "#{Time.zone.now}: localizing #{self.name} in #{study.name} to #{download_location}"
          puts msg
          Rails.logger.info msg
          file_location = File.join(study.data_store_path, self.download_location)
          Study.firecloud_client.execute_gcloud_method(:download_workspace_file, 0, study.bucket_id, self.bucket_location,
                                                       download_location, verify: :none)
          content_type = self.determine_content_type
          shift_headers = true
          if content_type == 'application/gzip'
            msg = "#{Time.zone.now}: Parsing #{self.name}:#{self.id} as application/gzip"
            puts msg
            Rails.logger.info msg
            file = Zlib::GzipReader.open(file_location)
          else
            msg = "#{Time.zone.now}: Parsing #{self.name}:#{self.id} as text/plain"
            puts msg
            Rails.logger.info msg
            file = File.open(file_location, 'rb')
          end
          raw_cells = file.readline.rstrip.split(/[\t,]/).map(&:strip)
          cells = self.study.sanitize_input_array(raw_cells)
          if shift_headers
            cells.shift
          end
          # close file
          file.close
          # add processed cells to known cells
          cells.each_slice(DataArray::MAX_ENTRIES).with_index do |slice, index|
            msg = "#{Time.zone.now}: Create known cells array ##{index + 1} for #{self.name}:#{self.id} in #{study.name}"
            puts msg
            Rails.logger.info msg
            known_cells = DataArray.new(name: "#{self.name} Cells", cluster_name: self.name, array_type: 'cells',
                                        array_index: index + 1, values: slice, study_file_id: self.id, study_id: self.study_id,
                                        linear_data_type: 'Study', linear_data_id: self.study_id)
            known_cells.save
          end
          msg = "#{Time.zone.now}: removing local copy of #{download_location}"
          self.remove_local_copy
        else
          msg = "#{Time.zone.now}: skipping #{self.name} in #{study.name}; remote file no longer exists"
          puts msg
          Rails.logger.error msg
        end
      else
        msg = "#{Time.zone.now}: skipping #{self.name} in #{study.name}; already processed"
        puts msg
        Rails.logger.info msg
      end
    rescue => e
      msg = "#{Time.zone.now}: error processing #{self.name} in #{self.study.name}: #{e.message}"
      puts msg
      Rails.logger.error msg
    end
  end

  # helper to return domain_ranges for clusters when launching ingest run
  def get_cluster_domain_ranges
    domain_ranges = {}
    if !self.x_axis_min.nil? && !self.x_axis_max.nil? && !self.y_axis_min.nil? && !self.y_axis_max.nil?
      domain_ranges = {
          x: [self.x_axis_min, self.x_axis_max],
          y: [self.y_axis_min, self.y_axis_max]
      }
      if !self.z_axis_min.nil? && !self.z_axis_max.nil?
        domain_ranges[:z] = [self.z_axis_min, self.z_axis_max]
      end
    end
    domain_ranges
  end

  private

  ###
  #
  # CUSTOM VALIDATIONS & CALLBACKS
  #
  ###

  # strip whitespace from name if the file is a cluster or gene list (will cause problems when rendering)
  def sanitize_name
    if ['Gene List', 'Cluster'].include?(self.file_type)
      self.name.strip!
    end
  end

  # set filename and construct url safe name from study
  def set_file_name_and_data_dir
    if self.upload_file_name.nil?
      self.status = 'uploaded'
      if self.name.nil?
        self.name = ''
      end
    elsif (self.name.nil? || self.name.blank?) || (!self.new_record? && self.upload_file_name != self.name)
      self.name = self.upload_file_name
    end
    self.data_dir = self.study.data_dir
  end

  # set ranges for cluster_groups if necessary
  def set_cluster_group_ranges
    if self.file_type == 'Cluster' && self.cluster_groups.any?
      cluster = self.cluster_groups.first
      # check if range values are present and set accordingly
      if !self.x_axis_min.nil? && !self.x_axis_max.nil? && !self.y_axis_min.nil? && !self.y_axis_max.nil?
        domain_ranges = {
            x: [self.x_axis_min, self.x_axis_max],
            y: [self.y_axis_min, self.y_axis_max]
        }
        if !self.z_axis_min.nil? && !self.z_axis_max.nil?
          domain_ranges[:z] = [self.z_axis_min, self.z_axis_max]
        end
        cluster.update(domain_ranges: domain_ranges)
      else
        # either user has not supplied ranges or is deleting them, so clear entry for cluster_group
        cluster.update(domain_ranges: nil)
      end
    end
  end

  # handler to set certain options based on a study_file's file_type
  def set_options_by_file_type
    case self.file_type
    when 'Ideogram Annotations'
      Rails.logger.info "Setting ideogram annotations options on #{self.upload_file_name}"
      unless self.options[:annotation_name].present? && self.options[:cluster_name].present?
        options_parts = self.upload_file_name.split('ideogram_exp_means__').last
        # chomp off filename header and .json at end
        options_parts.gsub!(/\.json/, '')
        cluster_name, annotation_name, annotation_type, annotation_scope = options_parts.split('--')
        annotation_identifier = [annotation_name, annotation_type, annotation_scope].join('--')
        self.update(options: {
            cluster_name: cluster_name,
            annotation_name: annotation_identifier,
            analysis_name: 'infercnv',
            visualization_name: 'ideogram.js'
        })
      end
      Rails.logger.info "Ideogram annotation successfully set on: #{self.upload_file_name}"
    end
  end

  # depending on the file_type, configure correct sanitizer for name field
  def validate_name_by_file_type
    regex = ValidationTools::FILENAME_CHARS
    error = ValidationTools::FILENAME_CHARS_ERROR
    case self.file_type
    when /(Cluster|Gene List)/
      regex = ValidationTools::OBJECT_LABELS
      error = ValidationTools::OBJECT_LABELS_ERROR
    when 'Fastq'
      if self.human_data?
        regex = ValidationTools::OBJECT_LABELS
        error = ValidationTools::OBJECT_LABELS_ERROR
      end
    end
    if self.name !~ regex
      errors.add(:name, error)
    end
  end

  # if this file is expression or sequence data, validate that the user has supplied a species/taxon
  def check_taxon
    if Taxon.present? && TAXON_REQUIRED_TYPES.include?(self.file_type) && self.taxon_id.blank?
      errors.add(:taxon_id, 'You must supply a species for this file type: ' + self.file_type)
    end
  end

  def check_assembly
    if GenomeAssembly.present? && ASSEMBLY_REQUIRED_TYPES.include?(self.file_type) && self.genome_assembly_id.nil?
      errors.add(:genome_assembly_id, 'You must supply a genome assembly for this file type: ' + self.file_type)
    end
  end

  # ensure that a user can only add one metadata file per study
  def ensure_metadata_singleton
    if StudyFile.where(file_type: 'Metadata', study_id: self.study_id, queued_for_deletion: false, :id.ne => self.id).exists?
      errors.add(:file_type, 'You may only add one metadata file per study')
    end
  end
end
