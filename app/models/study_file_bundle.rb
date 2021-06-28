class StudyFileBundle
  include Mongoid::Document
  include Mongoid::Timestamps
  include Swagger::Blocks
  field :bundle_type, type: String
  field :original_file_list, type: Array, default: []

  belongs_to :study
  has_many :study_files

  # allowed bundle types
  BUNDLE_TYPES = ['MM Coordinate Matrix', 'BAM', 'Cluster']
  # file types that must be bundled to be valid
  REQUIRE_BUNDLE = ['MM Coordinate Matrix', 'BAM', 'BAM Index', 'Coordinate Labels', '10X Genes File', '10X Barcodes File']
  # required keys for file list
  FILE_LIST_KEYS = %w(name file_type)
  # child file type requirements by bundle type
  BUNDLE_REQUIREMENTS = {
      'MM Coordinate Matrix' => ['10X Genes File', '10X Barcodes File'],
      'BAM' => ['BAM Index'],
      'Cluster' => ['Coordinate Labels']
  }
  # inverse of BUNDLE_REQUIREMENTS - this shows the required parent file type for each "bundled" file type
  # this is used in the upload wizard for error handling when a user uploads a bundled file, but the parent
  # has been deleted while the upload was in progress
  CHILD_REQUIREMENTS = {
    '10X Genes File' => 'MM Coordinate Matrix',
    '10X Barcodes File' => 'MM Coordinate Matrix',
    'BAM Index' => 'BAM',
    'Coordinate Labels' => 'Cluster'
  }
  PARSEABLE_BUNDLE_REQUIREMENTS = BUNDLE_REQUIREMENTS.dup.keep_if {|k,v| k != 'BAM'}
  FILE_ARRAY_ATTRIBUTES = {
      name: 'String',
      file_type: {
          values: StudyFile::STUDY_FILE_TYPES
      }
  }
  REQUIRED_ATTRIBUTES = %w(bundle_type original_file_list)
  # map of 'study_file.options[key_name]' for accessing parent study_file ID values, via upload/sync pages
  PARENT_FILE_OPTIONS_KEYNAMES = {
      'MM Coordinate Matrix' => 'matrix_id',
      'BAM' => 'bam_id',
      'Cluster' => 'cluster_file_id'
  }

  swagger_schema :StudyFileBundle do
    key :required, [:bundle_type, :original_file_list]
    key :name, 'StudyFileBundle'
    property :id do
      key :type, :string
    end
    property :study_id do
      key :type, :string
      key :description, 'ID of Study this StudyFileBundle belongs to'
    end
    property :bundle_type do
      key :type, :string
      key :enum, BUNDLE_TYPES
      key :description, 'Type of StudyFileBundle'
    end
    property :original_file_list do
      key :type, :array
      key :description, 'Original array of files to bundle together'
      items type: :object do
        key :required, [:name, :file_type]
        key :title, 'File object'
        property :name do
          key :type, :string
        end
        property :file_type do
          key :type, :string
          key :enum, StudyFile::STUDY_FILE_TYPES
        end
      end
    end
    property :study_files do
      key :type, :array
      key :description, 'Array of StudyFiles in this StudyFileBundle'
      items do
        key :title, 'StudyFile'
        key :'$ref', :StudyFile
      end
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

  swagger_schema :StudyFileBundleInput do
    allOf do
      schema do
        property :study_file_bundle do
          key :type, :object
          property :bundle_type do
            key :type, :string
            key :enum, BUNDLE_TYPES
            key :description, 'Type of StudyFileBundle'
          end
          property :original_file_list do
            key :type, :array
            key :description, 'Array of StudyFiles to bundle together'
            items type: :object do
              key :required, [:name, :file_type]
              key :title, 'File object'
              property :name do
                key :type, :string
              end
              property :file_type do
                key :type, :string
                key :enum, StudyFile::STUDY_FILE_TYPES
              end
            end
          end
        end
      end
    end
  end

  before_validation :set_bundle_type, on: :create
  validates_presence_of :bundle_type, :original_file_list
  validates_inclusion_of :bundle_type, in: BUNDLE_TYPES
  validate :validate_file_list_contents, on: :create
  after_validation :initialize_study_file_associations, on: :create

  before_destroy :remove_bundle_associations

  # parent file of this bundle (same as bundle_type)
  def parent
    self.study_files.find_by(file_type: self.bundle_type)
  end

  # child/dependent files in this bundle
  def bundled_files
    self.study_files.where(:id.ne => self.parent.id)
  end

  def file_types
    self.study_files.map(&:file_type)
  end

  def original_file_types
    self.original_file_list.map {|file| file['file_type']}
  end

  # determine if this is a completed bundle
  def completed?
    child_files = self.bundled_files
    child_file_types = child_files.map {|file| file['file_type']}
    if child_file_types.size < BUNDLE_REQUIREMENTS[self.bundle_type].size || ( (child_file_types.size == BUNDLE_REQUIREMENTS[self.bundle_type].size) &&
        (child_file_types & BUNDLE_REQUIREMENTS[self.bundle_type] != child_file_types))
      return false
    end
    if child_file_types.size > BUNDLE_REQUIREMENTS[self.bundle_type].size
      return false
    end
    # make sure all files have at least uploaded to the server
    self.study_files.each do |study_file|
      if !study_file.uploaded?
        return false
      end
    end
    true
  end

  # add files to an existing bundle if they meet requirements
  def add_files(*files)
    Rails.logger.info "Adding #{files.map(&:upload_file_name).join(', ')} to bundle #{self.bundle_type}:#{self.id} in #{self.study.name}"
    files.each do |file|
      file.update!(study_file_bundle_id: self.id)
    end
    additional_files = StudyFileBundle.generate_file_list(*files)
    self.original_file_list += additional_files
    self.save!
    Rails.logger.info "File addition to bundle #{self.bundle_type}:#{self.id} successful"
  end

  # helper to format requirements from constants into pretty-printed messages
  def self.swagger_requirements
    JSON.pretty_generate(BUNDLE_REQUIREMENTS)
  end

  # helper to generate a file list from input study files
  def self.generate_file_list(*files)
    files.map {|file| {'name' => file.upload_file_name, 'file_type' => file.file_type}}
  end

  def self.initialize_from_parent(study, parent_file)
    Rails.logger.info "Initializing study file bundle in #{study.name} from #{parent_file.upload_file_name}:#{parent_file.file_type}"
    possible_bundles = study.study_file_bundles.by_type(parent_file.file_type)
    study_file_bundle = possible_bundles.detect {|bundle| bundle.parent == parent_file}
    if study_file_bundle.present?
      Rails.logger.info "Found existing bundle: #{study_file_bundle.id}"
      study_file_bundle
    else
      Rails.logger.info "No bundle present, initializing new"
      file_list = [{'name' => parent_file.upload_file_name, 'file_type' => parent_file.file_type}]
      self.create(study_id: study.id, bundle_type: parent_file.file_type, original_file_list: file_list)
    end
  end

  private

  # from the original_file_types list, find the file that matches the bundle type
  def match_bundle_type
    self.original_file_types & BUNDLE_TYPES
  end

  def set_bundle_type
    unless self.bundle_type.present?
      if match_bundle_type.size == 1
        self.bundle_type = match_bundle_type.first
      end
    end
  end

  # make sure the original_file_list is in the correct format for extracting file information
  def validate_file_list_contents
    keys = self.original_file_list.map(&:keys).flatten.uniq.sort
    unless (keys & FILE_LIST_KEYS) == keys
      errors.add(:original_file_list, " is formatted incorrectly.  This must be an array of Hashes with the keys #{FILE_LIST_KEYS.join(', ')}." )
    end
    self.original_file_list.each do |file|
      unless StudyFile::STUDY_FILE_TYPES.include?(file['file_type'])
        errors.add(:original_file_list, " contains a file of an invalid type: #{file['file_type']}")
      end
    end
    unless match_bundle_type.any?
      errors.add(:original_file_list, " does not contain a file of the specified bundle type: #{self.bundle_type}")
    end
    if match_bundle_type.size > 1
      errors.add(:original_file_types, " contains files of incompatible types: #{match_bundle_type.join(', ')}")
    end
  end

  # set study_file associations after successful validation
  def initialize_study_file_associations
    self.original_file_list.each do |file_entry|
      filename = file_entry['name']
      file_type = file_entry['file_type']
      species_name = file_entry['species']
      assembly_name = file_entry['assembly']
      study_file = StudyFile.find_by(file_type: file_type, upload_file_name: filename, study_id: self.study_id, queued_for_deletion: false)
      if study_file.present?
        study_file.update(study_file_bundle_id: self.id)
      else
        study_file = self.study.study_files.build(file_type: file_type, upload_file_name: filename, study_file_bundle_id: self.id, name: filename)
        if StudyFile::TAXON_REQUIRED_TYPES.include?(file_type) && Taxon.present?
          study_file.taxon_id = Taxon.first.id # temporarily set arbitrary taxon association
          if species_name.present?
            taxon = Taxon.where(common_name: /#{species_name}/i).first
            taxon.present? ? study_file.taxon_id : nil # set requested taxon if we find it
          end
        end
        if StudyFile::ASSEMBLY_REQUIRED_TYPES.include?(file_type) && GenomeAssembly.present?
          study_file.genome_assembly_id = GenomeAssembly.first.id # temporarily set arbitrary assembly association
          if species_name.present?
            assembly = GenomeAssembly.where(name: /#{assembly_name}/i).first
            assembly.present? ? study_file.genome_assembly_id : nil # set requested assembly if we find it
          end
        end
        study_file.save!
      end
    end
  end

  # unset all associations on delete
  def remove_bundle_associations
    self.study_files.update_all(study_file_bundle_id: nil)
  end
end
