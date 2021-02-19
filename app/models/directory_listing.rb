class DirectoryListing

  ###
  #
  # DirectoryListing: object that holds metadata about groups of files in a specific location in a GCS bucket
  # Mainly used to supply blanket descriptions for all files at given location
  #
  ###

  include Mongoid::Document
  include Mongoid::Timestamps
  include Swagger::Blocks
  include Rails.application.routes.url_helpers # for accessing download_file_path and download_private_file_path

  PRIMARY_DATA_TYPES = %w(fq fastq).freeze
  READ_PAIR_IDENTIFIERS = %w(_R1 _R2 _I1 _I2).freeze
  FILE_ARRAY_ATTRIBUTES = {
      name: 'String',
      size: 'Integer',
      generation: 'String'
  }
  REQUIRED_ATTRIBUTES = %w(study_id name file_type files)
  TAXON_REQUIRED_REGEX = /(fastq|fq)/
  IGNORED_EXTENTIONS = %w(txt) # other file extentions to ignore
  MIN_SIZE = 10 # threshold of like file types required for creating DirectoryListing

  belongs_to :study
  belongs_to :taxon, optional: true

  field :name, type: String
  field :description, type: String
  field :file_type, type: String
  field :files, type: Array
  field :sync_status, type: Boolean, default: false

  swagger_schema :DirectoryListing do
    key :required, [:name, :file_type, :files]
    key :name, 'DirectoryListing'
    property :id do
      key :type, :string
    end
    property :study_id do
      key :type, :string
      key :description, 'ID of Study this StudyShare belongs to'
    end
    property :taxon_id do
      key :type, :string
      key :description, 'ID of Taxon (species) this DirectoryListing belongs to'
    end
    property :name do
      key :type, :string
      key :description, 'Name of remote GCS directory containing files'
    end
    property :description do
      key :type, :string
      key :format, :email
      key :description, 'Block description for all files contained in DirectoryListing'
    end
    property :file_type do
      key :type, :string
      key :description, 'File type (i.e. extension) of all files contained in DirectoryListing'
    end
    property :files do
      key :type, :array
      key :description, 'Array of file objects'
      items type: :object do
        key :title, 'GCS File object'
        key :required, [:name, :size, :generation]
        property :name do
          key :type, :string
          key :description, 'name of File'
        end
        property :size do
          key :type, :integer
          key :description, 'size of File'
        end
        property :generation do
          key :type, :string
          key :description, 'GCS generation tag of File'
        end
      end
    end
    property :sync_status do
      key :type, :boolean
      key :description, 'Boolean indication whether this DirectoryListing has been synced (and made available for download)'
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

  swagger_schema :DirectoryListingInput do
    allOf do
      schema do
        property :directory_listing do
          key :'$ref', :DirectoryListing
        end
      end
    end
  end

  validates_uniqueness_of :name, scope: [:study_id, :file_type]
  validates_presence_of :name, :file_type, :files
  validates_format_of :name, with: ValidationTools::FILENAME_CHARS,
                      message: ValidationTools::FILENAME_CHARS_ERROR
  validates_format_of :description, with: ValidationTools::OBJECT_LABELS,
            message: ValidationTools::OBJECT_LABELS_ERROR, allow_blank: true
  validates_format_of :file_type, with: ValidationTools::FILENAME_CHARS,
                      message: ValidationTools::FILENAME_CHARS_ERROR

  validate :check_taxon, on: :update
  validate :check_files_array_format

  index({ name: 1, study_id: 1, file_type: 1 }, { unique: true, background: true })

  # check if a directory_listing has a file
  def has_file?(filename)
    !self.files.detect(filename).nil?
  end

  # helper to generate correct urls for downloading fastq files
  def download_path(file)
    if self.study.public?
      download_file_path(accession: self.study.accession, study_name: self.study.url_safe_name, filename: file)
    else
      download_private_file_path(accession: self.study.accession, study_name: self.study.url_safe_name, filename: file)
    end
  end

  # output path for bulk download
  def bulk_download_pathname(file)
    "#{self.study.accession}/#{bulk_download_folder(file)}"
  end

  # helper to get total number of bytes in directory
  def total_bytes
    self.files.map {|file| file[:size].to_i}.reduce(:+) # to_i handles any nil file sizes
  end

  # location of a given file in a bulk download directory
  def bulk_download_folder(file)
    self.name == '/' ? "root_dir/#{file[:name]}": file[:name]
  end

  # helper to render name appropriately for use in download modals
  def download_display_name
    if self.name == '/'
      self.name
    else
      '/' + self.name + '/'
    end
  end

  # helper for setting DOM attributes that are URL-encoded
  def url_safe_name
    if self.name == '/'
      'root-dir'
    else
      self.name
    end
  end

  # guess at a possible sample name based on filename
  def possible_sample_name(filename)
    filename.split('/').last.split('.').first
  end

  # generate a gs-url to a file in the files list in the study's GCS bucket
  def gs_url(filename)
    if self.has_file?(filename)
      "gs://#{self.study.bucket_id}/#{filename}"
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

  # helper to return genome annotation, if present
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

  # return sample name based on filename (everything to the left of _(R|I)(1|2) string in file basename)
  # will also transform periods into underscores as these are unallowed in FireCloud
  def self.sample_name(filename)
    basename = self.file_basename(filename)
    DirectoryListing::READ_PAIR_IDENTIFIERS.each do |identifier|
      index = basename.index(identifier)
      if index
        return basename[0..index - 1].gsub(/\./, '_')
      else
        next
      end
    end
    basename
  end

  def self.read_position(filename)
    DirectoryListing::READ_PAIR_IDENTIFIERS.each do |identifier|
      if filename.match(/#{identifier}/)
        return DirectoryListing::READ_PAIR_IDENTIFIERS.index(identifier)
      end
    end
    0 # in case no pairing info is found, return 0 for first position
  end

  # method to return a mapping of samples and paired reads based on contents of a file list
  def self.sample_read_pairings(files)
    map = {}
    files.each do |file|
      sample = DirectoryListing.sample_name(file[:name])
      map[sample] ||= []
      # determine 'position' of read, i.e. 0-3 based on presence of read identifier in filename
      position = DirectoryListing.read_position(file[:name])
      map[sample][position] = file[:gs_url]
    end
    map
  end

  # create a mapping of file extensions and counts based on a list of input files from a google bucket
  # keys to map are the path at which groups of files are found, and values are key/value pairs of file
  # extensions and counts
  def self.create_extension_map(files, map={})
    files.map(&:name).each do |name|
      # don't use directories in extension map
      unless name.end_with?('/')
        path = self.get_folder_name(name)
        ext = self.file_extension(name)
        # don't store primary data filetypes in map as these are handled separately
        # also ignore any file types in IGNORED_EXTENTIONS
        unless DirectoryListing::PRIMARY_DATA_TYPES.any? {|e| ext.include?(e)} ||
            DirectoryListing::IGNORED_EXTENTIONS.include?(ext)
          if map[path].nil?
            map[path] = {"#{ext}" => 1}
          elsif map[path][ext].nil?
            map[path][ext] = 1
          else
            map[path][ext] += 1
          end
        end
      end
    end
    map
  end

  # helper to return file extension for a given filename
  def self.file_extension(filename)
    parts = filename.split('.')
    size = parts.size
    if parts[size - 2] == 'tar' && parts.last == 'gz'
      # handle tar.gz files first, returning '[ext].tar.gz'
      parts[(size - 3)..(size - 1)].join('.')
    elsif parts.last == 'gz'
      # if the file is a gzip archive, return '[ext].gz'
      parts[(size - 2)..(size - 1)].join('.')
    else
      parts.last
    end
  end

  # get basename of file (everything in front of extension)
  def self.file_basename(filename)
    # in case the file is in a directory in the bucket, trim off the directory name(s)
    actual_filename = filename.split('/').last
    actual_filename.chomp(".#{self.file_extension(actual_filename)}")
  end

  # get the 'folder' of a file in a bucket based on its pathname
  def self.get_folder_name(filepath)
    filepath.include?('/') ? filepath.split('/').first : '/'
  end

  private

  # if this directory is sequence data, validate that the user has supplied a species and assembly (only if syncing)
  def check_taxon
    if Taxon.present? && self.file_type.match(TAXON_REQUIRED_REGEX).present? && self.sync_status
      if self.taxon_id.nil?
        errors.add(:taxon_id, 'You must supply a species for this file type: ' + self.file_type)
      end
    end
  end

  # make sure that the files array is in the correct format
  def check_files_array_format
    error_msg = 'has invalid entries.  Each entry must be a hash with the keys of name (String), size (Integer), and '\
                'generation (String).  The following entries are invalid: '
    has_error = false
    self.files.each do |file|
      unless file.keys.map(&:to_s).sort == %w(generation name size)
        error_msg += "#{file}"
      end
    end
    if has_error
      errors.add(:files, error_msg)
    end
  end
end
