class Taxon
  include Mongoid::Document
  include ValidationTools
  include Swagger::Blocks

  has_many :study_files
  has_many :directory_listings
  has_many :genome_assemblies, dependent: :destroy do
    def latest
      order(release_date: :desc).first
    end
  end

  accepts_nested_attributes_for :genome_assemblies, allow_destroy: true
  belongs_to :user

  field :common_name, type: String
  field :scientific_name, type: String
  field :ncbi_taxid, type: Integer
  field :aliases, type: String
  field :restricted, type: Boolean, default: false
  field :notes, type: String

  validates_presence_of :common_name, :scientific_name, :ncbi_taxid, :notes
  validates_uniqueness_of :ncbi_taxid, :common_name, :scientific_name
  validates_format_of :common_name, :scientific_name, with: ALPHANUMERIC_SPACE_DASH,
                      message: ALPHANUMERIC_SPACE_DASH_ERROR

  before_destroy :remove_study_file_associations

  # Constants for scoping values for AnalysisParameter inputs/outputs
  ASSOCIATED_MODEL_METHOD = %w(common_name scientific_name ncbi_taxid)
  ASSOCIATED_MODEL_DISPLAY_METHOD = %w(common_name scientific_name ncbi_taxid)
  OUTPUT_ASSOCIATION_ATTRIBUTE = %w(study_file_id)
  ASSOCIATION_FILTER_ATTRIBUTE = %w(common_name scientific_name)

  swagger_schema :Taxon do
    key :required, [:common_name, :scientific_name, :ncbi_taxid]
    key :name, 'Taxon'
    property :id do
      key :type, :string
    end
    property :common_name do
      key :type, :string
      key :description, 'Common name of this taxon/specie'
    end
    property :scientific_name do
      key :type, :string
      key :description, 'Scientific name of this taxon/specie'
    end
    property :ncbi_taxid do
      key :type, :integer
      key :description, 'NCBI Taxon ID'
    end
    property :restricted do
      key :type, :boolean
      key :description, 'Restriction on adding primary sequence data from this species to portal'
    end
    property :aliases do
      key :type, :string
      key :description, 'Comma-delimited list of aliases for this taxon/specie'
    end
    property :notes do
      key :type, :string
      key :description, 'Notes about this entry'
    end
    property :genome_assemblies do
      key :type, :array
      key :description, 'Genome Assemblies for this taxon/specie'
      items type: :object do
        key :title, 'GenomeAssembly'
        key :required, [:name, :release_date]
        property :name do
          key :type, :string
          key :description, 'Name of genome assembly'
        end
        property :release_date do
          key :type, :string
          key :format, :date
          key :description, 'Public release date of genome assembly'
        end
        property :alias do
          key :type, :string
          key :description, 'Alias for this genome assembly'
        end
        property :genome_annotations do
          key :type, :array
          key :description, 'Genome Annotations for this assembly'
          items type: :object do
            key :title, 'GenomeAnnotation'
            key :required, [:name, :link, :index_link, :release_date]
            property :name do
              key :type, :string
              key :description, 'Name of genome annotation'
            end
            property :link do
              key :type, :string
              key :description, 'URL or relative GCS path to annotation file'
            end
            property :index_link do
              key :type, :string
              key :description, 'URL or relative GCS path to annotation index file'
            end
            property :release_date do
              key :type, :string
              key :format, :date
              key :description, 'Public release date of genome annotation'
            end
          end
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

  def self.sorted
    self.all.order_by(common_name: :asc)
  end

  def display_name
    "#{self.common_name}"
  end

  def current_assembly
    self.genome_assemblies.latest
  end

  # parser to auto-add taxons, and assemblies from an uploaded file, returning number of new entities
  def self.parse_from_file(tempfile_upload, user)
    if tempfile_upload.is_a?(ActionDispatch::Http::UploadedFile)
      file = File.open(tempfile_upload.tempfile.path)
      original_filename = tempfile_upload.original_filename
    elsif tempfile_upload.is_a?(Pathname)
      file = File.open(tempfile_upload)
      original_filename = tempfile_upload.basename.to_s
    elsif tempfile_upload.is_a?(File)
      file = tempfile_upload
      original_filename = file.path.split('/').last
    end
    num_species = 0
    num_assemblies = 0
    num_annotations = 0
    headers = file.readline.split("\t").map(&:strip)
    if headers.first.starts_with?('#')
      headers.first.gsub!(/#\s/, '') # remove hash sign if present
    end
    common_name_idx = headers.index('common_name')
    scientific_name_idx = headers.index('scientific_name')
    taxid_idx = headers.index('taxid')
    restricted_idx = headers.index('restricted')
    # genome assembly fields
    assembly_name_idx = headers.index('assembly_name')
    assembly_accession_idx = headers.index('assembly_accession')
    assembly_release_date_idx = headers.index('assembly_release_date')
    # genome annotation fields
    annot_name_idx = headers.index('annotation_name')
    annot_release_date_idx = headers.index('annotation_release_date')
    annot_link_idx = headers.index('annotation_url')
    annot_index_link_idx = headers.index('annotation_index_url')
    # load reference bucket workspace for use in parsing annotation links
    reference_ws_config = AdminConfiguration.find_by(config_type: 'Reference Data Workspace')
    if reference_ws_config.present?
      project, workspace = reference_ws_config.value.split('/')
      ref_workspace = ApplicationController.firecloud_client.get_workspace(project, workspace)
      bucket_id = ref_workspace['workspace']['bucketName']
    end
    while !file.eof?
      vals = file.readline.split("\t").map(&:strip)
      # check if all we're adding is another assembly
      taxon = Taxon.find_or_create_by(ncbi_taxid: vals[taxid_idx].to_i)
      taxon.common_name = vals[common_name_idx]
      taxon.scientific_name = vals[scientific_name_idx]
      taxon.ncbi_taxid = vals[taxid_idx]
      taxon.restricted = restricted_idx.present? ? vals[restricted_idx].downcase == 'true' : false
      taxon.user = user
      taxon.notes = "Uploaded from #{original_filename} on #{Date.today}"
      taxon.save!
      num_species += 1
      assembly = taxon.genome_assemblies.find_by(accession: vals[assembly_accession_idx])
      if assembly.nil?
        assembly = taxon.genome_assemblies.build
      end
      assembly.name = vals[assembly_name_idx]
      assembly.accession = vals[assembly_accession_idx]
      assembly.release_date = vals[assembly_release_date_idx]
      assembly.save!
      num_assemblies += 1
      # only add annotations if all fields are present, need to check that headers are there and that there are values
      if annot_name_idx.present? && annot_release_date_idx.present? && annot_link_idx.present? && annot_index_link_idx.present? &&
      !vals[annot_name_idx].blank? && !vals[annot_release_date_idx].blank? && !vals[annot_link_idx].blank? && !vals[annot_index_link_idx].blank?
        annotation = assembly.genome_annotations.find_by(name: vals[annot_name_idx])
        if annotation.nil?
          annotation = assembly.genome_annotations.build
        end
        annotation.name = vals[annot_name_idx]
        annotation.release_date = vals[annot_release_date_idx]
        # handle annotation links according to content
        annotation.link = process_annotation_link_value(vals[annot_link_idx], bucket_id)
        annotation.index_link = process_annotation_link_value(vals[annot_index_link_idx], bucket_id)
        annotation.save!
        num_annotations += 1
      end
    end
    {new_species: num_species, new_assemblies: num_assemblies, new_annotations: num_annotations}
  end

  private

  def remove_study_file_associations
    self.study_files.update_all(taxon_id: nil)
  end

  def self.process_annotation_link_value(link, bucket_id)
    # determine if this is an external url, or a link to a file in the reference bucket
    if bucket_id.present? && link.include?(bucket_id)
      processed_link = link.split(bucket_id).last
      # trim of leading slash if present
      processed_link.starts_with?('/') ? processed_link[1..-1] : processed_link
    else
      link
    end
  end
end
