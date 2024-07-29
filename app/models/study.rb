class Study

  ###
  #
  # Study: main object class for portal; stores information regarding study objects and references to FireCloud workspaces,
  # access controls to viewing study objects, and also used as main parsing class for uploaded study files.
  #
  ###

  include Mongoid::Document
  include Mongoid::Timestamps
  extend ValidationTools
  include Swagger::Blocks
  include Mongoid::History::Trackable

  # feature flag integration
  include FeatureFlaggable

  ###
  #
  # FIRECLOUD METHODS
  #
  ###

  # prefix for FireCloud workspaces, defaults to blank in production
  REQUIRED_ATTRIBUTES = %w(name)

  # Constants for scoping values for AnalysisParameter inputs/outputs
  ASSOCIATED_MODEL_METHOD = %w(bucket_id firecloud_project firecloud_workspace url_safe_name workspace_url google_bucket_url gs_url)
  ASSOCIATED_MODEL_DISPLAY_METHOD = %w(name url_safe_name bucket_id firecloud_project firecloud_workspace workspace_url google_bucket_url gs_url)
  OUTPUT_ASSOCIATION_ATTRIBUTE = %w(id)

  ###
  #
  # SETTINGS, ASSOCIATIONS AND SCOPES
  #
  ###

  # pagination
  def self.per_page
    10
  end

  # associations and scopes
  belongs_to :user
  has_and_belongs_to_many :branding_groups

  has_many :authors, dependent: :delete_all do
    def corresponding
      where(corresponding: true)
    end
  end
  accepts_nested_attributes_for :authors, allow_destroy: :true

  has_many :publications, dependent: :delete_all do
    def published
      where(preprint: false)
    end
  end
  accepts_nested_attributes_for :publications, allow_destroy: :true

  has_many :study_files, dependent: :delete_all do
    # all study files not queued for deletion
    def available
      where(queued_for_deletion: false)
    end

    def by_type(file_type)
      if file_type.is_a?(Array)
        available.where(:file_type.in => file_type).to_a
      else
        available.where(file_type: file_type).to_a
      end
    end

    def non_primary_data
      available.not_in(file_type: StudyFile::PRIMARY_DATA_TYPES).to_a
    end

    def primary_data
      available.in(file_type: StudyFile::PRIMARY_DATA_TYPES).to_a
    end

    # all files that have been pushed to the bucket (will have the generation tag)
    def valid
      available.where(:generation.ne => nil).to_a
    end

    # includes links to external data which do not reside in the workspace bucket
    def downloadable
      available.where.any_of({ :generation.ne => nil }, { :human_fastq_url.ne => nil })
    end

    # all files not queued for deletion, ignoring newly built files
    def persisted
      available.reject(&:new_record?)
    end
  end
  accepts_nested_attributes_for :study_files, allow_destroy: true

  has_many :study_file_bundles, dependent: :destroy do
    def by_type(file_type)
      if file_type.is_a?(Array)
        where(:bundle_type.in => file_type)
      else
        where(bundle_type: file_type)
      end
    end
  end

  has_many :genes do
    def by_name_or_id(term, study_file_ids)
      all_matches = any_of({name: term, :study_file_id.in => study_file_ids},
                            {searchable_name: term.downcase, :study_file_id.in => study_file_ids},
                            {gene_id: term, :study_file_id.in => study_file_ids})
      if all_matches.empty?
        []
      else
        # since we can have duplicate genes but not cells, merge into one object for rendering
        # allow for case-sensitive matching over case-insensitive
        exact_matches = all_matches.select {|g| g.name == term}
        if exact_matches.any?
          data = exact_matches
        else
          # group by searchable name to find any possible case sensitivity issues, then uniquify by study_file_id
          # this will drop any fuzzy matches caused by case insensitivity that would lead to merging genes
          # that were intended to be unique
          data = all_matches.group_by(&:searchable_name).values.map {|group| group.uniq(&:study_file_id)}.flatten
        end
        merged_scores = {'searchable_name' => data.first.searchable_name, 'name' => data.first.name, 'scores' => {}}
        data.each do |score|
          merged_scores['scores'].merge!(score.scores)
        end
        merged_scores
      end
    end
  end

  has_many :precomputed_scores do
    def by_name(name)
      where(name: name).first
    end
  end

  has_many :study_shares, dependent: :destroy do
    def can_edit
      where(permission: 'Edit').map(&:email)
    end

    def can_view
      all.to_a.map(&:email)
    end

    def non_reviewers
      where(:permission.nin => %w(Reviewer)).map(&:email)
    end

    def reviewers
      where(permission: 'Reviewer').map(&:email)
    end

    def visible
      if ApplicationController.read_only_firecloud_client.present?
        readonly_issuer = ApplicationController.read_only_firecloud_client.issuer
        where(:email.not => /#{readonly_issuer}/).map(&:email)
      else
        all.to_a.map(&:email)
      end
    end
  end
  accepts_nested_attributes_for :study_shares, allow_destroy: true, reject_if: proc { |attributes| attributes['email'].blank? }

  has_many :cluster_groups do
    def by_name(name)
      find_by(name: name)
    end
  end

  has_many :data_arrays, as: :linear_data do
    def by_name_and_type(name, type)
      where(name: name, array_type: type).order_by(&:array_index)
    end
  end

  has_many :cell_metadata do
    def by_name_and_type(name, type)
      find_by(name: name, annotation_type: type)
    end
  end

  has_many :directory_listings do
    def unsynced
      where(sync_status: false).to_a
    end

    # all synced directories, regardless of type
    def are_synced
      where(sync_status: true).to_a
    end

    # synced directories of a specific type
    def synced_by_type(file_type)
      where(sync_status: true, file_type: file_type).to_a
    end

    # primary data directories
    def primary_data
      where(sync_status: true, :file_type.in => DirectoryListing::PRIMARY_DATA_TYPES).to_a
    end

    # non-primary data directories
    def non_primary_data
      where(sync_status: true, :file_type.nin => DirectoryListing::PRIMARY_DATA_TYPES).to_a
    end
  end

  # User annotations are per study
  has_many :user_annotations
  has_many :user_data_arrays

  # HCA metadata object
  has_many :analysis_metadata, dependent: :delete_all

  # Study Accession
  has_one :study_accession

  # External Resource links
  has_many :external_resources, as: :resource_links, dependent: :destroy
  accepts_nested_attributes_for :external_resources, allow_destroy: true

  # DownloadAgreement (extra user terms for downloading data)
  has_one :download_agreement, dependent: :delete_all
  accepts_nested_attributes_for :download_agreement, allow_destroy: true

  # Study Detail (full html description)
  has_one :study_detail, dependent: :delete_all
  accepts_nested_attributes_for :study_detail, allow_destroy: true

  # Anonymous Reviewer Access
  has_one :reviewer_access, dependent: :delete_all
  accepts_nested_attributes_for :reviewer_access, allow_destroy: true

  has_many :differential_expression_results, dependent: :delete_all do
    def automated
      where(:is_author_de.in => [nil, false])
    end

    def author
      where(is_author_de: true)
    end
  end

  # field definitions
  field :name, type: String
  field :embargo, type: Date
  field :url_safe_name, type: String
  field :accession, type: String
  field :description, type: String
  field :firecloud_workspace, type: String
  field :firecloud_project, type: String, default: FireCloudClient::PORTAL_NAMESPACE
  field :bucket_id, type: String
  field :internal_workspace, type: String # workspace that holds internal bucket
  field :internal_bucket_id, type: String # for visualization assets, pare logs, etc
  field :data_dir, type: String
  field :public, type: Boolean, default: true
  field :queued_for_deletion, type: Boolean, default: false
  field :detached, type: Boolean, default: false # indicates whether workspace/bucket is missing
  field :initialized, type: Boolean, default: false
  field :view_count, type: Integer, default: 0
  field :cell_count, type: Integer, default: 0
  field :gene_count, type: Integer, default: 0
  field :view_order, type: Float, default: 100.0
  field :use_existing_workspace, type: Boolean, default: false
  field :default_options, type: Hash, default: {} # extensible hash where we can put arbitrary values as 'defaults'
  field :external_identifier, type: String # ID from external service, used for tracking via ImportService
  field :imported_from, type: String # Human-readable tag for external service that study was imported from, e.g. HCA
  ##
  #
  # SWAGGER DEFINITIONS
  #
  ##

  swagger_schema :Study do
    key :required, [:name]
    key :name, 'Study'
    property :id do
      key :type, :string
    end
    property :name do
      key :type, :string
      key :description, 'Name of Study'
    end
    property :embargo do
      key :type, :string
      key :format, :date
      key :description, 'Date used for restricting download access to StudyFiles in Study'
    end
    property :description do
      key :type, :string
      key :description, 'Plain text description blob for Study'
    end
    property :full_description do
      key :type, :string
      key :description, 'HTML description blob for Study (optional)'
    end
    property :url_safe_name do
      key :type, :string
      key :description, 'URL-encoded version of Study name'
    end
    property :accession do
      key :type, :string
      key :description, 'Accession (used in permalinks, not editable)'
    end
    property :firecloud_project do
      key :type, :string
      key :default, FireCloudClient::PORTAL_NAMESPACE
      key :description, 'Terra billing project to which Study firecloud_workspace belongs'
    end
    property :firecloud_workspace do
      key :type, :string
      key :description, 'Terra user-specific workspace that corresponds to this Study'
    end
    property :use_existing_workspace do
      key :type, :boolean
      key :default, false
      key :description, 'Boolean indication whether this Study used an existing FireCloud workspace when created'
    end
    property :bucket_id do
      key :type, :string
      key :description, 'GCS Bucket name where uploaded files are stored'
    end
    property :internal_workspace do
      key :type, :string
      key :description, 'Terra workspace that holds internal SCP assets'
    end
    property :internal_bucket_id do
      key :type, :string
      key :description, 'GCS Bucket name where internal SCP assets are stored'
    end
    property :data_dir do
      key :type, :string
      key :description, 'Local directory where uploaded files are localized to (for parsing)'
    end
    property :public do
      key :type, :boolean
      key :default, true
      key :description, 'Boolean indication of whether Study is publicly readable'
    end
    property :queued_for_deletion do
      key :type, :boolean
      key :default, false
      key :description, 'Boolean indication whether Study is queued for garbage collection'
    end
    property :branding_group_id do
      key :type, :string
      key :description, 'ID of BrandingGroup to which Study belongs, if present'
    end
    property :initialized do
      key :type, :boolean
      key :default, false
      key :description, 'Boolean indication of whether Study has at least one of all required StudyFile types parsed to enable visualizations (Expression Matrix, Metadata, Cluster)'
    end
    property :detached do
      key :type, :boolean
      key :default, false
      key :description, 'Boolean indication of whether Study has been \'detached\' from its FireCloud workspace, usually when the workspace is deleted directly in FireCloud'
    end
    property :view_count do
      key :type, :number
      key :format, :integer
      key :default, 0
      key :description, 'Number of times Study has been viewed in the portal'
    end
    property :cell_count do
      key :type, :number
      key :format, :integer
      key :default, 0
      key :description, 'Number of unique cell names in Study (set from Metadata StudyFile)'
    end
    property :gene_count do
      key :type, :number
      key :format, :integer
      key :default, 0
      key :description, 'Number of unique gene names in Study (set from Expression Matrix or 10X Genes File)'
    end
    property :view_order do
      key :type, :number
      key :format, :float
      key :default, 100.0
      key :description, 'Number used to control sort order in which Studies are returned when searching/browsing'
    end
    property :default_options do
      key :type, :object
      key :default, {}
      key :description, 'Key/Value storage of additional options'
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

  swagger_schema :StudyInput do
    allOf do
      schema do
        property :study do
          key :type, :object
          property :name do
            key :type, :string
            key :description, 'Name of Study'
          end
          property :embargo do
            key :type, :string
            key :format, :date
            key :description, 'Date used for restricting download access to StudyFiles in Study'
          end
          property :description do
            key :type, :string
            key :description, 'Plain text description blob for Study'
          end
          property :study_detail_attributes do
            key :type, :object
            property :full_description do
              key :type, :string
              key :description, 'HTML description blob for Study (optional)'
            end
          end
          property :firecloud_project do
            key :type, :string
            key :default, FireCloudClient::PORTAL_NAMESPACE
            key :description, 'FireCloud billing project to which Study firecloud_workspace belongs'
          end
          property :firecloud_workspace do
            key :type, :string
            key :description, 'FireCloud workspace that corresponds to this Study'
          end
          property :use_existing_workspace do
            key :type, :boolean
            key :default, false
            key :description, 'Boolean indication whether this Study used an existing FireCloud workspace when created'
          end
          key :required, [:name]
        end
      end
    end
  end

  swagger_schema :StudyUpdateInput do
    allOf do
      schema do
        property :study do
          key :type, :object
          property :name do
            key :type, :string
          end
          property :description do
            key :type, :string
          end
          property :embargo do
            key :type, :string
            key :format, :date
            key :description, 'Date used for restricting download access to StudyFiles in Study'
          end
          property :cell_count do
            key :type, :number
            key :format, :integer
            key :default, 0
            key :description, 'Number of unique cell names in Study (set from Metadata StudyFile)'
          end
          property :gene_count do
            key :type, :number
            key :format, :integer
            key :default, 0
            key :description, 'Number of unique gene names in Study (set from Expression Matrix or 10X Genes File)'
          end
          property :view_order do
            key :type, :number
            key :format, :float
            key :default, 100.0
            key :description, 'Number used to control sort order in which Studies are returned when searching/browsing'
          end
          property :study_detail_attributes do
            key :type, :object
            property :full_description do
              key :type, :string
              key :description, 'HTML description blob for Study (optional)'
            end
          end
          property :default_options do
            key :type, :object
            key :default, {}
            key :description, 'Key/Value storage of additional options'
          end
          property :branding_group_id do
            key :type, :string
            key :description, 'ID of branding group object to assign Study to (if present)'
          end
          key :required, [:name]
        end
      end
    end
  end

  swagger_schema :SiteStudy do
    property :name do
      key :type, :string
      key :description, 'Name of Study'
    end
    property :description do
      key :type, :string
      key :description, 'HTML description blob for Study'
    end
    property :accession do
      key :type, :string
      key :description, 'Accession (used in permalinks, not editable)'
    end
    property :public do
      key :type, :boolean
      key :default, true
      key :description, 'Boolean indication of whether Study is publicly readable'
    end
    property :detached do
      key :type, :boolean
      key :default, false
      key :description, 'Boolean indication of whether Study has been \'detached\' from its FireCloud workspace, usually when the workspace is deleted directly in FireCloud'
    end
    property :cell_count do
      key :type, :number
      key :format, :integer
      key :default, 0
      key :description, 'Number of unique cell names in Study (set from Metadata StudyFile)'
    end
    property :gene_count do
      key :type, :number
      key :format, :integer
      key :default, 0
      key :description, 'Number of unique gene names in Study (set from Expression Matrix or 10X Genes File)'
    end
  end

  swagger_schema :SiteStudyWithFiles do
    property :name do
      key :type, :string
      key :description, 'Name of Study'
    end
    property :description do
      key :type, :string
      key :description, 'Plain text description blob for Study'
    end
    property :full_description do
      key :type, :string
      key :description, 'HTML description blob for Study'
    end
    property :accession do
      key :type, :string
      key :description, 'Accession (used in permalinks, not editable)'
    end
    property :public do
      key :type, :boolean
      key :default, true
      key :description, 'Boolean indication of whether Study is publicly readable'
    end
    property :detached do
      key :type, :boolean
      key :default, false
      key :description, 'Boolean indication of whether Study has been \'detached\' from its FireCloud workspace, usually when the workspace is deleted directly in FireCloud'
    end
    property :cell_count do
      key :type, :number
      key :format, :integer
      key :default, 0
      key :description, 'Number of unique cell names in Study (set from Metadata StudyFile)'
    end
    property :gene_count do
      key :type, :number
      key :format, :integer
      key :default, 0
      key :description, 'Number of unique gene names in Study (set from Expression Matrix or 10X Genes File)'
    end
    property :study_files do
      key :type, :array
      key :description, 'Available StudyFiles for download/streaming'
      items do
        key :title, 'StudyFile'
        key '$ref', 'SiteStudyFile'
      end
    end
    property :directory_listings do
      key :type, :array
      key :description, 'Available Directories of files for bulk download'
      items do
        key :title, 'DirectoryListing'
        key '$ref', 'DirectoryListingDownload'
      end
    end
    property :publications do
      key :type, :array
      key :description, 'Available publications'
      items do
        key :title, 'Publication'
        key '$ref', :PublicationInput
      end
    end
    property :external_resources do
      key :type, :array
      key :description, 'Available external resource links'
      items do
        key :title, 'ExternalResource'
        key '$ref', :ExternalResourceInput
      end
    end
  end

  swagger_schema :SearchStudyWithFiles do
    property :name do
      key :type, :string
      key :description, 'Name of Study'
    end
    property :description do
      key :type, :string
      key :description, 'HTML description blob for Study'
    end
    property :accession do
      key :type, :string
      key :description, 'Accession (used in permalinks, not editable)'
    end
    property :public do
      key :type, :boolean
      key :default, true
      key :description, 'Boolean indication of whether Study is publicly readable'
    end
    property :detached do
      key :type, :boolean
      key :default, false
      key :description, 'Boolean indication of whether Study has been \'detached\' from its FireCloud workspace, usually when the workspace is deleted directly in FireCloud'
    end
    property :cell_count do
      key :type, :number
      key :format, :integer
      key :default, 0
      key :description, 'Number of unique cell names in Study (set from Metadata StudyFile)'
    end
    property :study_url do
      key :type, :string
      key :description, 'Relative URL path to view study'
    end
    property :facet_matches do
      key :type, :object
      key :description, 'SearchFacet filter matches'
    end
    property :term_matches do
      key :type, :array
      key :description, 'Keyword term matches'
      items do
        key :title, 'TermMatch'
        key :type, :string
      end
    end
    property :term_search_weight do
      key :type, :integer
      key :description, 'Relevance of term match'
    end
    property :inferred_match do
      key :type, :boolean
      key :description, 'Indication if match is inferred (e.g. converting facet filter value to keyword search)'
    end
    property :preset_match do
      key :type, :boolean
      key :description, 'Indication this study was included by a preset search'
    end
    property :gene_matches do
      key :type, :array
      key :description, 'Array of ids of the genes that were matched for this study'
      items do
        key :title, 'gene match'
        key :type, :string
      end
    end
    property :can_visualize_clusters do
      key :type, :boolean
      key :description, 'Whether this study has cluster visualization data available'
    end
    property :study_files do
      key :type, :object
      key :title, 'StudyFiles'
      key :description, 'Available StudyFiles for download, by type'
      StudyFile::BULK_DOWNLOAD_TYPES.each do |file_type|
        property file_type do
          key :description, "#{file_type} Files"
          key :type, :array
          items do
            key :title, 'StudyFile'
            key '$ref', 'SiteStudyFile'
          end
        end
      end
    end
  end


  ###
  #
  # VALIDATIONS & CALLBACKS
  #
  ###

  # custom validator since we need everything to pass in a specific order (otherwise we get orphaned FireCloud workspaces)
  validate :initialize_with_new_workspace, on: :create, if: Proc.new {|study| !study.use_existing_workspace && !study.detached}
  validate :initialize_with_existing_workspace, on: :create, if: Proc.new {|study| study.use_existing_workspace}

  # populate specific errors for associations since they share the same form
  validate do |study|
    %i[study_shares authors publications].each do |association_name|
      study.send(association_name).each_with_index do |model, index|
        next if model.valid?

        model.errors.full_messages.each do |msg|
          indicator = "#{index + 1}#{(index + 1).ordinal}"
          errors.add(:base, "#{indicator} #{model.class} Error - #{msg}")
        end
        errors.delete(association_name) if errors[association_name].present?
      end
    end
    # get errors for reviewer_access, if any
    if study.reviewer_access.present? && !study.reviewer_access.valid?
      study.reviewer_access.errors.full_messages.each do |msg|
        errors.add(:base, msg)
      end
    end
  end

  # XSS protection
  validate :strip_unsafe_characters_from_description
  validates_format_of :name, with: ValidationTools::OBJECT_LABELS,
                      message: ValidationTools::OBJECT_LABELS_ERROR

  validates_format_of :firecloud_workspace, :firecloud_project, :internal_workspace,
                      with: ValidationTools::ALPHANUMERIC_SPACE_DASH, message: ValidationTools::ALPHANUMERIC_SPACE_DASH_ERROR

  validates_format_of :data_dir, :bucket_id, :internal_bucket_id, :url_safe_name,
                      with: ValidationTools::ALPHANUMERIC_DASH, message: ValidationTools::ALPHANUMERIC_DASH_ERROR

  # update validators
  validates_uniqueness_of :name, on: :update, message: ": %{value} has already been taken.  Please choose another name."
  validates_presence_of   :name, on: :update
  validate :prevent_firecloud_attribute_changes, on: :update
  validates_uniqueness_of :external_identifier, allow_blank: true
  validates :cell_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate  :assign_accession, on: :create
  validate  :set_internal_workspace_name, on: :create
  validate  :create_internal_workspace, on: :create, unless: proc { |study| study.detached }
  validates_presence_of :firecloud_project, :firecloud_workspace, :internal_workspace

  # callbacks
  before_validation :set_url_safe_name
  before_validation :set_data_dir, :set_firecloud_workspace_name, on: :create

  # before_save       :verify_default_options
  after_create      :make_data_dir, :set_default_participant, :check_bucket_read_access
  before_destroy    :ensure_cascade_on_associations
  after_destroy     :remove_data_dir
  before_save       :set_readonly_access

  # search definitions
  index({"name" => "text", "description" => "text"}, {background: true})
  index({accession: 1}, {unique: true})
  ###
  #
  # ACCESS CONTROL METHODS
  #
  ###

  # return all studies that are editable by a given user
  def self.editable(user)
    if user.admin?
      self.where(queued_for_deletion: false)
    else
      studies = self.where(queued_for_deletion: false, user_id: user._id)
      shares = StudyShare.where(email: /#{user.email}/i, permission: 'Edit').map(&:study).select {|s| !s.queued_for_deletion }
      [studies + shares].flatten.uniq
    end
  end

  # return all studies that are viewable by a given user as a Mongoid criterion
  def self.viewable(user)
    if user.nil?
      self.where(queued_for_deletion: false, public: true)
    elsif user.admin?
      self.where(queued_for_deletion: false)
    else
      public = self.where(public: true, queued_for_deletion: false).map(&:id)
      owned = self.where(user_id: user._id, public: false, queued_for_deletion: false).map(&:id)
      shares = StudyShare.where(email: /#{user.email}/i).map(&:study).select {|s| !s.queued_for_deletion }.map(&:id)
      group_shares = user.user_groups
      intersection = public + owned + shares + group_shares
      # return Mongoid criterion object to use with pagination
      Study.in(:_id => intersection)
    end
  end

  # return all studies either owned by or shared with a given user as a Mongoid criterion
  def self.accessible(user, check_groups: true)
    if user.admin?
      self.where(queued_for_deletion: false)
    else
      owned = self.where(user_id: user._id, queued_for_deletion: false).map(&:_id)
      shares = StudyShare.where(email: /#{user.email}/i).map(&:study).select {|s| !s.queued_for_deletion }.map(&:_id)
      group_shares = check_groups ? user.user_groups : []
      intersection = owned + shares + group_shares
      Study.in(:_id => intersection)
    end
  end

  # check if a give use can edit study
  # check_groups can be set to false to skip checking group shares (for performance)
  def can_edit?(user, check_groups: true)
    if user.nil?
      false
    else
      if admins.map(&:downcase).include?(user.email.downcase)
        true
      elsif check_groups
        user_in_group_share?(user, 'Edit')
      else
        false
      end
    end
  end

  # google allows arbitrary periods in email addresses so if the email is a gmail account remove any excess periods
  def remove_gmail_periods(email_address)
    email_address = email_address.downcase
    return email_address unless email_address.end_with?('gmail.com')
    # sub out any periods with blanks, then replace the period for the '.com' at the end of the address
    email_address = email_address.gsub('.', '').gsub(/com\z/, '.com')
  end

  # check if a given user can view study by share (does not take public into account - use Study.viewable(user) instead)
  # check_groups can be set to false to skip checking group shares (for performance)
  def can_view?(user, check_groups: true)
    if user.nil?
      false
    else
      # use if/elsif with explicit returns to ensure skipping downstream calls
      if study_shares.can_view.map do |email_address|
        remove_gmail_periods(email_address)
      end.include?(remove_gmail_periods(user.email))
        return true
      elsif can_edit?(user, check_groups:)
        return true
      elsif check_groups
        return user_in_group_share?(user, 'View', 'Reviewer')
      end
    end
    false
  end

  # check if a user has access to a study's GCS bucket.  will require View or Edit permission at the user or group level
  def has_bucket_access?(user)
    if user.nil?
      false
    else
      if self.user == user
        return true
      elsif self.study_shares.non_reviewers.map(&:downcase).include?(user.email.downcase)
        return true
      else
        self.user_in_group_share?(user, 'View', 'Edit')
      end
    end
  end

  # call Rawls to check bucket access for a given user (defaults to main service account)
  # if a user should have access, but doesn't (403 response) then a FastPass request is issued to speed up the process
  # this is mainly used as a proxy for synchronizing service account bucket access faster in non-default projects
  def check_bucket_read_access(user: nil)
    return nil if detached # exit for studies with no workspace

    client = user ? FireCloudClient.new(user:) : FireCloudClient.new
    client.check_bucket_read_access(firecloud_project, firecloud_workspace)
    if internal_workspace
      client.check_bucket_read_access(FireCloudClient::PORTAL_NAMESPACE, internal_workspace)
    end
  end

  # always run :check_bucket_read_access in the background at lower priority
  # can be invoked in the foreground with :check_bucket_read_access_without_delay
  handle_asynchronously :check_bucket_read_access, priority: 10

  # check if a user has permission do download data from this study (either is public and user is signed in, user is an admin, or user has a direct share)
  def can_download?(user)
    if self.public? && user.present?
      return true
    elsif user.present? && user.admin?
      return true
    else
      self.has_bucket_access?(user)
    end
  end

  # check if user can delete a study - only owners can
  def can_delete?(user)
    self.user_id == user.id || user.admin?
  end

  # check if a user can run workflows on the given study
  def can_compute?(user)
    if user.nil? || !user.registered_for_firecloud?
      false
    else
      # don't check permissions if API is not 'ok'
      if ApplicationController.firecloud_client.services_available?(FireCloudClient::SAM_SERVICE, FireCloudClient::RAWLS_SERVICE, FireCloudClient::AGORA_SERVICE)
        begin
          workspace_acl = ApplicationController.firecloud_client.get_workspace_acl(self.firecloud_project, self.firecloud_workspace)
          if workspace_acl['acl'][user.email].nil?
            # check if user has project-level permissions
            user.is_billing_project_owner?(self.firecloud_project)
          else
            workspace_acl['acl'][user.email]['canCompute']
          end
        rescue => e
          ErrorTracker.report_exception(e, user, { study: self.attributes.to_h})
          Rails.logger.error "Unable to retrieve compute permissions for #{user.email}: #{e.message}"
          false
        end
      else
        false
      end
    end
  end

  # check if a user has access to a study via a user group
  def user_in_group_share?(user, *permissions)
    # check if api status is ok, otherwise exit without checking to prevent UI hanging on repeated calls
    if user.registered_for_firecloud && ApplicationController.firecloud_client.services_available?(FireCloudClient::SAM_SERVICE, FireCloudClient::RAWLS_SERVICE, FireCloudClient::THURLOE_SERVICE)
      group_shares = self.study_shares.keep_if {|share| share.is_group_share?}.select {|share| permissions.include?(share.permission)}.map(&:email)
      # get user's groups via user.user_groups which includes token setting & error handling
      user_groups = user.user_groups
      # use native array intersection to determine if any of the user's groups have been shared with this study at the correct permission
      (user_groups & group_shares).any?
    else
      false # if user is not registered for firecloud, default to false
    end
  end

  # list of emails for accounts that can edit this study
  def admins
    [self.user.email, self.study_shares.can_edit, User.where(admin: true).pluck(:email)].flatten.uniq
  end

  # array of user accounts associated with this study (study owner + shares); can scope by permission, if provided
  # differs from study.admins as it does not include portal admins
  def associated_users(permission: nil)
    owner = self.user
    shares = permission.present? ? self.study_shares.where(permission: permission) : self.study_shares
    share_users = shares.map { |share| User.find_by(email: /#{share.email}/i) }.compact
    [owner] + share_users
  end

  # check if study is still under embargo or whether given user can bypass embargo
  def embargoed?(user)
    if user.nil?
      embargo_active?
    else
      # must not be viewable by current user & embargoed to be true
      !can_view?(user) && embargo_active?
    end
  end

  # helper method to check embargo status
  def embargo_active?
    embargo.blank? ? false : Time.zone.today < embargo
  end

  def has_download_agreement?
    self.download_agreement.present? ? !self.download_agreement.expired? : false
  end

  # label for study visibility
  def visibility
    self.public? ? "<span class='sc-badge bg-success text-success'>Public</span>".html_safe : "<span class='sc-badge bg-danger text-danger'>Private</span>".html_safe
  end

  # helper method to return key-value pairs of sharing permissions local to portal (not what is persisted in FireCloud)
  # primarily used when syncing study with FireCloud workspace
  def local_acl
    acl = {
        "#{self.user.email}" => (Rails.env.production? && FireCloudClient::COMPUTE_DENYLIST.include?(self.firecloud_project)) ? 'Edit' : 'Owner'
    }
    self.study_shares.each do |share|
      acl["#{share.email}"] = share.permission
    end
    acl
  end

  # compute a simplistic relevance score by counting instances of terms in names/descriptions
  def search_weight(terms)
    weights = {
        total: 0,
        terms: {}
    }
    terms.each do |term|
      author_names = authors.pluck(:first_name, :last_name, :institution).flatten.join(' ')
      text_blob = "#{self.name} #{self.description} #{author_names}"
      score = text_blob.scan(/#{::Regexp.escape(term)}/i).size
      if score > 0
        weights[:total] += score
        weights[:terms][term] = score
      end
    end
    weights
  end

  ###
  #
  # DATA VISUALIZATION GETTERS
  #
  # used to govern rendering behavior on /app/views/site/_study_visualize.html
  ##

  def has_expression_data?
    self.genes.any?
  end

  def has_cluster_data?
    self.cluster_groups.any?
  end

  def has_cell_metadata?
    self.cell_metadata.any?
  end

  def has_gene_lists?
    self.precomputed_scores.any?
  end

  def can_visualize_clusters?
    self.has_cluster_data? && self.has_cell_metadata?
  end

  def can_visualize_genome_data?
    self.has_track_files? || self.has_analysis_outputs?('infercnv', 'ideogram.js')
  end

  def can_visualize?
    self.can_visualize_clusters? || self.can_visualize_genome_data? || self.has_gene_lists?
  end

  def has_raw_counts_matrices?
    self.expression_matrices.where('expression_file_info.is_raw_counts' => true).exists?
  end

  def has_visualization_matrices?
    self.expression_matrices.any_of({'expression_file_info.is_raw_counts' => false}, {expression_file_info: nil}).exists?
  end

  # check if study has any files that can be streamed from the bucket for visualization
  # this includes BAM, BED, inferCNV Ideogram annotations, Image files, and DE files
  #
  # TODO (SCP-4336):
  # This is currently only used for getting auth tokens.  Consider incorporating this
  # into existing endpoints, or perhaps a new endpoint, where the token is returned as part
  # of the API response.
  def has_streamable_files(user)
    has_track_files? || # BAM or BED
    has_analysis_outputs?('infercnv', 'ideogram.js') ||
    user && user.feature_flag_for('differential_expression_frontend') ||
    feature_flag_for('differential_expression_frontend')
  end

  # quick getter to return any cell metadata that can_visualize?
  def viewable_metadata
    viewable = []
    all_metadata = self.cell_metadata
    all_names = all_metadata.pluck(:name)
    all_metadata.each do |meta|
      if meta.annotation_type == 'numeric'
        viewable << meta
      else
        if CellMetadatum::GROUP_VIZ_THRESHOLD === meta.values.size
          viewable << meta unless all_names.include?(meta.name + '__ontology_label')
        end
      end
    end
    viewable
  end

  # helper to determine if a study has any publications/external resources to link to from the study overview page
  def has_sidebar_content?
    publications.any? || external_resources.any? || authors.corresponding.any?
  end

  ###
  #
  # DATA PATHS & URLS
  #
  ###

  # file path to study public folder
  def data_public_path
    Rails.root.join('public', 'single_cell', 'data', self.url_safe_name)
  end

  # file path to upload storage directory
  def data_store_path
    Rails.root.join('data', self.data_dir)
  end

  # helper to generate a URL to a study's FireCloud workspace,  either user-controlled or internal
  def workspace_url(type = :study)
    "https://app.terra.bio/#workspaces/#{workspace_attrs(type).join('/')}"
  end

  # helper to generate an HTTPS URL to a study's GCP bucket, either user-controlled or visualization-related
  def google_bucket_url(type = :study)
    "https://accounts.google.com/AccountChooser?continue=" \
    "https://console.cloud.google.com/storage/browser/#{google_bucket_name(type)}"
  end

  # array of Terra namespace/name attributes for a given workspace type
  def workspace_attrs(type = :study)
    case type
    when :study
      [firecloud_project, firecloud_workspace]
    when :internal
      [FireCloudClient::PORTAL_NAMESPACE, internal_workspace]
    else
      [firecloud_project, firecloud_workspace]
    end
  end

  def gs_url(type = :study)
    "gs://#{google_bucket_name(type)}"
  end

  # determine correct bucket_id for given type
  def google_bucket_name(type = :study)
    case type
    when :study
      bucket_id
    when :internal
      internal_bucket_id
    else
      bucket_id
    end
  end

  # helper to generate a URL to a specific FireCloud submission inside a study's GCP bucket
  def submission_url(submission_id)
    self.google_bucket_url + "/#{submission_id}"
  end

  ###
  #
  # DEFAULT OPTIONS METHODS
  #
  ###

  # helper to return default cluster to load, will fall back to first cluster if no pf has been set
  # or default cluster cannot be loaded
  def default_cluster
    default = self.cluster_groups.first
    unless self.default_options[:cluster].nil?
      new_default = self.cluster_groups.by_name(self.default_options[:cluster])
      unless new_default.nil?
        default = new_default
      end
    end
    default
  end

  # Returns default_annotation_params in string form [[name]]--[[type]]--[[scope]]
  # to match the UI and how they're stored in default_options
  def default_annotation(cluster=self.default_cluster)
    params = default_annotation_params(cluster)
    params.present? ? "#{params[:name]}--#{params[:type]}--#{params[:scope]}" : nil
  end

  # helper to return default annotation to load, will fall back to first available annotation if no preference has been set
  # or default annotation cannot be loaded.  returns a hash of {name: ,type:, scope: }
  def default_annotation_params(cluster=default_cluster)
    default_annot = default_options[:annotation]
    annot_params = nil
    # in case default has not been set
    if default_annot.nil?
      if !cluster.nil? && cluster.cell_annotations.any?
        annot = cluster.cell_annotations.select { |annot| cluster.can_visualize_cell_annotation?(annot) }.first ||
          cluster.cell_annotations.first
        annot_params = {
          name: annot[:name],
          type: annot[:type],
          scope: 'cluster'
        }
      elsif cell_metadata.any?
        metadatum = cell_metadata.keep_if(&:can_visualize?).first || cell_metadata.first
        annot_params = {
          name: metadatum.name,
          type: metadatum.annotation_type,
          scope: 'study'
        }
      else
        # annotation won't be set yet if a user is parsing metadata without clusters, or vice versa
        annot_params = nil
      end
    else
      annot_params = {
        name: default_annotation_name,
        type: default_annotation_type,
        scope: default_annotation_scope
      }
    end
    annot_params
  end

  # helper to return default annotation type (group or numeric)
  def default_annotation_type
    if self.default_options[:annotation].blank?
      nil
    else
      # middle part of the annotation string is the type, e.g. Label--group--study
      self.default_options[:annotation].split('--')[1]
    end
  end

  # helper to return default annotation name
  def default_annotation_name
    if self.default_options[:annotation].blank?
      nil
    else
      # first part of the annotation string
      self.default_options[:annotation].split('--')[0]
    end
  end

  # helper to return default annotation scope
  def default_annotation_scope
    if self.default_options[:annotation].blank?
      nil
    else
      # last part of the annotation string
      self.default_options[:annotation].split('--')[2]
    end
  end

  # return color profile value, converting blanks to nils
  def default_color_profile
    self.default_options[:color_profile].presence
  end

  # array of names of annotations to ignore the unique values limit for visualizing
  def override_viz_limit_annotations
    self.default_options[:override_viz_limit_annotations] || []
  end

  # make an annotation visualizable despite exceeding the default values limit
  def add_override_viz_limit_annotation(annotation_name)
    cell_metadatum = self.cell_metadata.find_by(name: annotation_name)
    if cell_metadatum
      # we need to populate the 'values' array, since that will not have been done at ingest
      begin
        uniq_vals = cell_metadatum.concatenate_data_arrays(annotation_name, 'annotations').uniq
        cell_metadatum.update!(values: uniq_vals)
      rescue => e
        Rails.logger.error "Could not cache unique annotation values: #{e.message}"
        Rails.logger.error "This means values array will be fetched on-demand for visualization requests"
      end
    end

    updated_list = override_viz_limit_annotations
    updated_list.push(annotation_name)
    self.default_options[:override_viz_limit_annotations] = updated_list
    self.save!
    # clear the cache so that explore data is fetched correctly
    CacheRemovalJob.new(accession).perform
  end

  # return the value of the expression axis label
  def default_expression_label
    self.default_options[:expression_label].present? ? self.default_options[:expression_label] : 'Expression'
  end

  # determine if a user has supplied an expression label
  def has_expression_label?
    !self.default_options[:expression_label].blank?
  end

  # determine whether or not the study owner wants to receive update emails
  def deliver_emails?
    if self.default_options[:deliver_emails].nil?
      true
    else
      self.default_options[:deliver_emails]
    end
  end

  # default size for cluster points
  def default_cluster_point_size
    if self.default_options[:cluster_point_size].blank?
      3
    else
      self.default_options[:cluster_point_size].to_i
    end
  end

  # default size for cluster points
  def show_cluster_point_borders?
    if self.default_options[:cluster_point_border].blank?
      false
    else
      self.default_options[:cluster_point_border] == 'true'
    end
  end

  def default_cluster_point_alpha
    if self.default_options[:cluster_point_alpha].blank?
      1.0
    else
      self.default_options[:cluster_point_alpha].to_f
    end
  end

  ###
  #
  # INSTANCE VALUE SETTERS & GETTERS
  #
  ###

  # helper method to get number of unique single cells
  def set_cell_count
    cell_count = self.all_cells_array.size
    Rails.logger.info "Setting cell count in #{self.name} to #{cell_count}"
    self.update(cell_count: cell_count)
    Rails.logger.info "Cell count set for #{self.name}"
  end

  # helper method to set the number of unique genes in this study
  def set_gene_count
    gene_count = self.unique_genes.size
    Rails.logger.info "Setting gene count in #{self.name} to #{gene_count}"
    self.update(gene_count: gene_count)
    Rails.logger.info "Gene count set for #{self.name}"
  end

  # get all unique gene names for a study; leverage index on Gene model to improve performance
  def unique_genes
    Gene.where(study_id: self.id, :study_file_id.in => self.expression_matrix_files.map(&:id)).pluck(:name).uniq
  end

  # List unique scientific names of species for all expression matrices in study
  def expressed_taxon_names
    self.expression_matrix_files
      .map {|f| f.taxon.try(:scientific_name) }
      .uniq
  end

  # For a gene name in this study, get scientific name of species / organism
  # For example: "PTEN" -> ["Homo sapiens"].
  #
  # TODO (SCP-2769): Handle when a searched gene maps to multiple species
  def infer_taxons(gene_name)
    Gene
      .where(study_id: self.id, :study_file_id.in => self.expression_matrix_files.pluck(:id), name: gene_name)
      .map {|gene| gene.taxon.try(:scientific_name)}
      .uniq
  end

  # return a count of the number of fastq files both uploaded and referenced via directory_listings for a study
  def primary_data_file_count
    study_file_count = self.study_files.primary_data.size
    directory_listing_count = self.directory_listings.primary_data.map {|d| d.files.size}.reduce(0, :+)
    study_file_count + directory_listing_count
  end

  # count of all files in a study, regardless of type
  def total_file_count
    self.study_files.non_primary_data.count + self.primary_data_file_count
  end

  # return a count of the number of miscellanous files both uploaded and referenced via directory_listings for a study
  def misc_directory_file_count
    self.directory_listings.non_primary_data.map {|d| d.files.size}.reduce(0, :+)
  end

  # count the number of cluster-based annotations in a study
  def cluster_annotation_count
    self.cluster_groups.map {|c| c.cell_annotations.size}.reduce(0, :+)
  end

  # retrieve the full HTML description for this study
  def full_description
    self.study_detail.try(:full_description)
  end

  ###
  #
  # METADATA METHODS
  #
  ###

  # @deprecated use :all_cells_array
  # return an array of all single cell names in study
  def all_cells
    annot = self.study_metadata.first
    if annot.present?
      annot.cell_annotations.keys
    else
      []
    end
  end

  # return an array of all single cell names in study, will check for main list of cells or concatenate all
  # cell lists from individual expression matrices
  def all_cells_array
    if self.metadata_file&.parsed? # nil-safed via &
      query = {
        name: 'All Cells', array_type: 'cells', linear_data_type: 'Study', linear_data_id: self.id,
        study_id: self.id, study_file_id: self.metadata_file.id, cluster_group_id: nil, subsample_annotation: nil,
        subsample_threshold: nil
      }
      DataArray.concatenate_arrays(query)
    else
      all_expression_matrix_cells
    end
  end

  # return an array of all cell names that have been used in expression matrices (does not get cells from cell metadata file)
  def all_expression_matrix_cells
    all_cells = []
    expression_matrix_files.each do |file|
      all_cells += expression_matrix_cells(file)
    end
    all_cells.uniq # account for raw counts & processed matrix files repeating cell names
  end

  # for every cluster in this study, generate an indexed array of cluster cells using 'all cells' as the map
  # returns number of arrays created
  def create_all_cluster_cell_indices!
    return nil if cluster_groups.empty?

    cluster_groups.each do |cluster_group|
      Rails.logger.info "creating all cell name indices for #{accession}:#{cluster_group.name}"
      cluster_group.create_all_cell_indices!
      Rails.logger.info "finished cell name index for #{accession}:#{cluster_group.name}"
    end
  end

  # return the cells found in a single expression matrix
  def expression_matrix_cells(study_file)
    query = {
      name: "#{study_file.upload_file_name} Cells", array_type: 'cells', linear_data_type: 'Study',
      linear_data_id: self.id, study_file_id: study_file.id, cluster_group_id: nil, subsample_annotation: nil,
      subsample_threshold: nil
    }
    DataArray.concatenate_arrays(query)
  end

  # return a hash keyed by cell name of the requested study_metadata values
  def cell_metadata_values(metadata_name, metadata_type)
    cell_metadatum = self.cell_metadata.by_name_and_type(metadata_name, metadata_type)
    if cell_metadatum.present?
      cell_metadatum.cell_annotations
    else
      {}
    end
  end

  # return array of possible values for a given study_metadata annotation (valid only for group-based)
  def cell_metadata_keys(metadata_name, metadata_type)
    cell_metadatum = self.cell_metadata.by_name_and_type(metadata_name, metadata_type)
    if cell_metadatum.present?
      cell_metadatum.values
    else
      []
    end
  end

  # return a nested array of all available annotations, both cluster-specific and study-wide for use in auto-generated
  # dropdowns for selecting annotations.  can be scoped to one specific cluster, or return all with 'Cluster: ' prepended on the name
  def formatted_annotation_select(cluster: nil, annotation_type: nil)
    options = {}
    viewable = self.viewable_metadata
    metadata = annotation_type.nil? ? viewable : viewable.select {|m| m.annotation_type == annotation_type}
    options['Study Wide'] = metadata.map(&:annotation_select_option)
    if cluster.present?
      options['Cluster-Based'] = cluster.cell_annotation_select_option(annotation_type)
    else
      self.cluster_groups.each do |cluster_group|
        options[cluster_group.name] = cluster_group.cell_annotation_select_option(annotation_type, true) # prepend name onto option value
      end
    end
    options
  end

  ###
  #
  # STUDYFILE GETTERS
  #
  ###


  # helper to build a study file of the requested type
  def build_study_file(attributes)
    self.study_files.build(attributes)
  end

  def clustering_files
    study_files.any_of(
      { file_type: 'Cluster' },
      { file_type: 'AnnData', 'ann_data_file_info.has_clusters' => true }
    )
  end

  # helper method to access all cluster definitions files
  def cluster_ordinations_files
    clustering_files.to_a
  end

  # helper method to access cluster definitions file by name
  def cluster_ordinations_file(name)
    clustering_files.detect { |file| file.name == name }
  end

  # helper method to directly access expression matrix files
  def expression_matrix_files
    expression_matrices.to_a
  end

  # Mongoid criteria for expression files (rather than array of StudyFiles)
  def expression_matrices
    study_files.any_of(
      { :file_type.in => ['Expression Matrix', 'MM Coordinate Matrix'] },
      { file_type: 'AnnData', 'ann_data_file_info.has_expression' => true }
    )
  end

  # helper method to directly access expression matrix file by name
  def expression_matrix_file(name)
    expression_matrices.find_by(name:)
  end

  # helper method to directly access metadata file
  def metadata_file
    study_files.any_of(
      { file_type: 'Metadata' },
      { file_type: 'AnnData', 'ann_data_file_info.has_metadata' => true }
    ).first
  end

  # check if a study has analysis output files for a given analysis
  def has_analysis_outputs?(analysis_name, visualization_name=nil, cluster_name=nil, annotation_name=nil)
    self.get_analysis_outputs(analysis_name, visualization_name, cluster_name, annotation_name).any?
  end

  # return all study files for a given analysis & visualization component
  def get_analysis_outputs(analysis_name, visualization_name=nil, cluster_name=nil, annotation_name=nil)
    criteria = {
        'options.analysis_name' => analysis_name,
        :queued_for_deletion => false
    }
    if visualization_name.present?
      criteria.merge!('options.visualization_name' => visualization_name)
    end
    if cluster_name.present?
      criteria.merge!('options.cluster_name' => cluster_name)
    end
    if annotation_name.present?
      criteria.merge!('options.annotation_name' => annotation_name)
    end
    self.study_files.where(criteria)
  end

  # Return settings for this study's inferCNV ideogram visualization
  def get_ideogram_infercnv_settings(cluster_name, annotation_name)
    exp_file = self.get_analysis_outputs('infercnv', 'ideogram.js',
                                         cluster_name, annotation_name).first
    {
      'organism': exp_file.species_name,
      'assembly': exp_file.genome_assembly.try(:name),
      'annotationsPath': exp_file.api_url
    }
  end

  def has_track_files?
    self.study_files.by_type(['BAM', 'BED']).any?
  end

  # Get a list of igv.js track file objects where each object has a URL for
  # the track data itself and index URL for its matching index (BAI if BAM,
  # else TBI) file.
  def get_tracks

    track_files = self.study_files.by_type(['BAM', 'BED'])
    tracks = []

    track_files.each do |track_file|
      next unless track_file.has_completed_bundle?

      bundled_type = track_file.file_type == 'BAM' ? 'BAM Index' : 'Tab Index'

      tracks << {
          'format' => track_file.file_type.downcase,
          'name' => track_file.name,
          'url' => track_file.api_url,
          'indexUrl' => track_file.study_file_bundle.bundled_file_by_type(bundled_type)&.api_url,
          'genomeAssembly' => track_file.genome_assembly_name,
          'genomeAnnotation' => track_file.genome_annotation
      }
    end
    tracks
  end

  def get_genome_annotations_by_assembly
    genome_annotations = {}
    track_files = self.study_files.by_type(['BAM', 'BED'])
    track_files.each do |track_file|
      assembly = track_file.genome_assembly_name
      if !genome_annotations.key?(assembly)
        genome_annotations[assembly] = {}
      end
      genome_annotation = track_file.genome_annotation
      if !genome_annotations[assembly].key?(genome_annotation)

        # Only handle one annotation per genome assembly for now;
        # enhance to support multiple annotations when UI supports it
        genome_annotations[assembly]['genome_annotations'] = {
          'name': genome_annotation,
          'url': track_file.genome_annotation_link,
          'indexUrl': track_file.genome_annotation_index_link
        }
      end
    end
    genome_annotations
  end

  def taxons
    taxons = self.study_files.where(:file_type.in => StudyFile::TAXON_REQUIRED_TYPES).map(&:taxon)
    taxons.compact!
    taxons.uniq
  end

  ###
  #
  # DELETE METHODS
  #
  ###

  # nightly cron to delete any studies that are 'queued for deletion'
  # will run after database is re-indexed to make performance better
  # calls delete_all on collections to minimize memory usage
  def self.delete_queued_studies
    studies = self.where(queued_for_deletion: true)
    studies.each do |study|
      Rails.logger.info "#{Time.zone.now}: deleting queued study #{study.name}"
      # ensure_cascade_on_associations handles deleting parsed data
      study.destroy
      Rails.logger.info "#{Time.zone.now}: delete of #{study.name} completed"
    end
    true
  end

  ###
  #
  # MISCELLANOUS METHODS
  #
  ###

  # check if all files for this study are still present in the bucket
  # does not check generation tags for consistency - this is just a presence check
  def verify_all_remotes
    missing = []
    files = self.study_files.where(queued_for_deletion: false, human_data: false, :parse_status.ne => 'parsing', status: 'uploaded')
    directories = self.directory_listings.are_synced
    all_locations = files.map(&:bucket_location)
    all_locations += directories.map {|dir| dir.files.map {|file| file['name']}}.flatten
    remotes = ApplicationController.firecloud_client.execute_gcloud_method(:get_workspace_files, 0, self.bucket_id)
    if remotes.next?
      remotes = [] # don't use bucket list of files, instead verify each file individually
    end
    all_locations.each do |file_location|
      match = self.verify_remote_file(remotes: remotes, file_location: file_location)
      if match.nil?
        missing << {filename: file_location, study: self.name, owner: self.user.email, reason: "File missing from bucket: #{self.bucket_id}"}
      end
    end
    missing
  end

  # quick check to see if a single file is still in the study's bucket
  # can use cached list of bucket files, or check bucket directly
  def verify_remote_file(remotes:, file_location:)
    remotes.any? ? remotes.detect {|remote| remote.name == file_location} : ApplicationController.firecloud_client.execute_gcloud_method(:get_workspace_file, 0, self.bucket_id, file_location)
  end

  ###
  #
  # FIRECLOUD FILE METHODS
  #
  ###

  # shortcut method to send an uploaded file straight to firecloud from parser
  # will compress plain text files before uploading to reduce storage/egress charges
  def send_to_firecloud(file)
    begin
      Rails.logger.info "Uploading #{file.bucket_location}:#{file.id} to Terra workspace: #{firecloud_workspace}"
      was_gzipped = FileParseService.compress_file_for_upload(file)
      opts = was_gzipped ? { content_encoding: 'gzip' } : {}
      remote_file = ApplicationController.firecloud_client.execute_gcloud_method(
        :create_workspace_file, 0, bucket_id, file.upload.path, file.bucket_location, opts
      )
      # store generation tag to know whether a file has been updated in GCP
      Rails.logger.info "Updating #{file.bucket_location}:#{file.id} with generation tag: #{remote_file.generation} after successful upload"
      file.update(generation: remote_file.generation)
      Rails.logger.info "Upload of #{file.bucket_location}:#{file.id} complete, scheduling cleanup job"
      # schedule the upload cleanup job to run in two minutes
      run_at = 2.minutes.from_now
      Delayed::Job.enqueue(UploadCleanupJob.new(file.study, file, 0), run_at:)
      Rails.logger.info "cleanup job for #{file.bucket_location}:#{file.id} scheduled for #{run_at}"
    rescue => e
      ErrorTracker.report_exception(e, user, self, file)
      Rails.logger.error "Unable to upload '#{file.bucket_location}:#{file.id} to study bucket #{bucket_id}; #{e.message}"
      # notify admin of failure so they can push the file and relaunch parse
      SingleCellMailer.notify_admin_upload_fail(file, e).deliver_now
    end
  end

  ###
  #
  # PUBLIC CALLBACK SETTERS
  # These are methods that are called as a part of callbacks, but need to be public as they are also referenced elsewhere
  #
  ###

  # make data directory after study creation is successful
  # this is now a public method so that we can use it whenever remote files are downloaded to validate that the directory exists
  def make_data_dir
    unless Dir.exist?(self.data_store_path)
      FileUtils.mkdir_p(self.data_store_path)
    end
  end

  # set the 'default_participant' entity in workspace data to allow users to upload sample information
  def set_default_participant
    return if detached # skip if study is detached, which is common in test environment

    begin
      path = Rails.root.join('data', self.data_dir, 'default_participant.tsv')
      entity_file = File.new(path, 'w+')
      entity_file.write "entity:participant_id\ndefault_participant"
      entity_file.close
      upload = File.open(entity_file.path)
      ApplicationController.firecloud_client.import_workspace_entities_file(self.firecloud_project, self.firecloud_workspace, upload)
      Rails.logger.info "#{Time.zone.now}: created default_participant for #{self.firecloud_workspace}"
      File.delete(path)
    rescue => e
      ErrorTracker.report_exception(e, user, self)
      Rails.logger.error "Unable to set default participant: #{e.message}"
    end
  end

  # set the study_accession for this study
  def assign_accession
    next_accession = StudyAccession.next_available
    while Study.where(accession: next_accession).exists? || StudyAccession.where(accession: next_accession).exists?
      next_accession = StudyAccession.next_available
    end
    self.accession = next_accession
    StudyAccession.create(accession: next_accession, study_id: self.id)
  end

  # set access for the readonly service account if a study is public
  def set_readonly_access(grant_access=true, manual_set=false)
    unless Rails.env.test? || self.queued_for_deletion || self.detached
      if manual_set || self.public_changed? || self.new_record?
        if self.firecloud_workspace.present? && self.firecloud_project.present? && ApplicationController.read_only_firecloud_client.present?
          access_level = self.public? ? 'READER' : 'NO ACCESS'
          if !grant_access # revoke all access
            access_level = 'NO ACCESS'
          end
          Rails.logger.info "#{Time.zone.now}: setting readonly access on #{self.name} to #{access_level}"
          readonly_acl = ApplicationController.firecloud_client.create_workspace_acl(ApplicationController.read_only_firecloud_client.issuer, access_level, false, false)
          ApplicationController.firecloud_client.update_workspace_acl(self.firecloud_project, self.firecloud_workspace, readonly_acl)
        end
      end
    end
  end

  # check whether a study is "detached" (bucket/workspace missing)
  def set_study_detached_state(error)
    # missing bucket errors should have one of three messages
    #
    # nil:NilClass => returned from a NoMethodError when calling bucket.files
    # forbidden, does not have storage.buckets.get access => resulting from 403 when accessing bucket as ACLs
    # have been revoked pending delete
    if /(nil\:NilClass|does not have storage.buckets.get access|forbidden)/.match(error.message)
      Rails.logger.error "Marking #{self.name} as 'detached' due to error reading bucket files; #{error.class.name}: #{error.message}"
      self.update(detached: true)
    else
      # check if workspace is still available, otherwise mark detached
      begin
        ApplicationController.firecloud_client.get_workspace(self.firecloud_project, self.firecloud_workspace)
      rescue RestClient::Exception => e
        Rails.logger.error "Marking #{self.name} as 'detached' due to missing workspace: #{self.firecloud_project}/#{self.firecloud_workspace}"
        self.update(detached: true)
      end
    end
  end

  # deletes the study and its underlying workspace.  This method is disabled in production
  def destroy_and_remove_workspace
    if Rails.env.production?
      return
    end
    Rails.logger.info "Removing workspace #{firecloud_project}/#{firecloud_workspace} in #{Rails.env} environment"
    begin
      clean_up_workspaces
      DeleteQueueJob.new(self.metadata_file).delay.perform if self.metadata_file.present?
      destroy
    rescue => e
      Rails.logger.error "Error in removing #{firecloud_project}/#{firecloud_workspace}"
      Rails.logger.error "#{e.class.name}:"
      Rails.logger.error "#{e.message}"
      destroy # ensure deletion of study, even if workspace is orphaned
    end
    Rails.logger.info "Workspace #{firecloud_project}/#{firecloud_workspace} successfully removed."
  end

  # helper method that mimics DeleteQueueJob.delete_convention_data
  # referenced from ensure_cascade_on_associations to prevent orphaned rows in BQ on manual deletes
  def delete_convention_data
    if self.metadata_file.present? && self.metadata_file.use_metadata_convention
      Rails.logger.info "Removing convention data for #{self.accession} from BQ"
      bq_dataset = ApplicationController.big_query_client.dataset CellMetadatum::BIGQUERY_DATASET
      bq_dataset.query "DELETE FROM #{CellMetadatum::BIGQUERY_TABLE} WHERE study_accession = '#{self.accession}' AND file_id = '#{self.metadata_file.id}'"
      Rails.logger.info "BQ cleanup for #{self.accession} completed"
      SearchFacet.delay.update_all_facet_filters
    end
  end

  def last_public_date
    history_tracks.where('modified.public': true).order_by(created_at: :desc).first&.created_at
  end

  def last_initialized_date
    history_tracks.where('modified.initialized': true).order_by(created_at: :desc).first&.created_at
  end

  # determine correct FireCloudClient type to use, either user- or service account-based
  def workspace_client(project = firecloud_project)
    if project == FireCloudClient::PORTAL_NAMESPACE
      ApplicationController.firecloud_client
    else
      FireCloudClient.new(user:, project:)
    end
  end

  # ensure a user has requisite permissions on an existing workspace
  def user_has_workspace_access?
    client = workspace_client(firecloud_project)
    acl = client.get_workspace_acl(firecloud_project, firecloud_workspace)&.with_indifferent_access
    study_owner = user.email
    existing_acl = acl.dig(:acl, study_owner)
    write_access = existing_acl && %w[OWNER WRITER].include?(existing_acl[:accessLevel])
    if write_access
      Rails.logger.info "Study owner has sufficient permissions for #{firecloud_project}/#{firecloud_workspace}"
    else
      Rails.logger.info "checking project-level permissions for user_id:#{user.id} in #{firecloud_project}"
      unless user.is_billing_project_owner?(firecloud_project)
        errors.add(:firecloud_workspace, ': You do not have write permission for the workspace you provided.  Please use another workspace.')
        return false
      end
      Rails.logger.info "project-level permissions check successful"
    end
    true
  end

  # determine if the requested billing project is valid to use
  def billing_project_ok?
    return true if firecloud_project == FireCloudClient::PORTAL_NAMESPACE

    projects = workspace_client(firecloud_project).get_billing_projects.map { |project| project['projectName'] }
    projects.include?(firecloud_project)
  end

  # public version of create_internal_workspace to use in backfill migration
  # will assign internal_workspace and internal_bucket_id
  def add_internal_workspace
    set_internal_workspace_name if internal_workspace.blank?
    ws_namespace, ws_name = workspace_attrs(:internal)
    client = workspace_client(ws_namespace)
    if client.workspace_exists?(ws_namespace, ws_name)
      Rails.logger.info "#{accession} already has internal workspace: #{ws_namespace}/#{ws_name}"
      return nil
    end
    workspace = create_terra_workspace(:internal)
    Rails.logger.info "#{accession} Terra internal workspace #{internal_workspace} creation successful"
    assign_workspace_acls!(:internal)
    Rails.logger.info "#{accession} Terra internal workspace acls assigned successfully"
    set_bucket_id(workspace['bucketName'], type: :internal)
    save!
    Rails.logger.info "#{accession} Terra internal workspace creation complete"
    client.check_bucket_read_access(ws_namespace, ws_name)
    workspace
  end

  private

  ###
  #
  # SETTERS
  #
  ###

  # sets a url-safe version of study name (for linking)
  def set_url_safe_name
    self.url_safe_name = self.name.downcase.gsub(/[^a-zA-Z0-9]+/, '-').chomp('-')
  end

  # set the FireCloud workspace name to be used when creating study
  # will only set the first time, and will not set if user is initializing from an existing workspace
  def set_firecloud_workspace_name
    unless self.use_existing_workspace
      self.firecloud_workspace = self.url_safe_name
    end
  end

  # set the data directory to a random value to use as a temp location for uploads while parsing
  # this is useful as study deletes will happen asynchronously, so while the study is marked for deletion we can allow
  # other users to re-use the old name & url_safe_name
  # will only set the first time
  def set_data_dir
    @dir_val = SecureRandom.hex(32)
    while Study.where(data_dir: @dir_val).exists?
      @dir_val = SecureRandom.hex(32)
    end
    self.data_dir = @dir_val
  end

  # set bucket ID after workspace creation
  def set_bucket_id(bucket, type: :study)
    case type
    when :study
      self.bucket_id = bucket
    when :internal
      self.internal_bucket_id = bucket
    else
      self.bucket_id = bucket
    end
    true
  end

  # set the internal workspace name
  # will be called after study accession is assigned
  # adds extra 5-character slug in test environment to avoid name collisions
  def set_internal_workspace_name
    if accession.present?
      workspace = "#{accession}-#{Rails.env}-internal"
      workspace += "-#{SecureRandom.alphanumeric(5)}" if Rails.env.test?
      self.internal_workspace = workspace
    else
      errors.add(:internal_workspace, 'Unable to assign internal workspace, study accession not set')
    end
  end

  ###
  #
  # CUSTOM VALIDATIONS
  #
  ###

  # create requested workspace type
  def create_and_validate_workspace(workspace_type)
    workspace = create_terra_workspace(workspace_type)
    Rails.logger.info "'#{name}' Terra #{workspace_type} workspace creation successful"
    acls_assigned = assign_workspace_acls!(workspace_type)
    if !acls_assigned
      requested_workspace = workspace_type == :study ? :firecloud_workspace : :internal_workspace
      errors.add(requested_workspace, ": We encountered an error when attempting to set workspace permissions.  Please try again, or chose a different project.")
      return false
    else
      Rails.logger.info "'#{name}' acls ok for #{workspace_type} workspace #{workspace_attrs(workspace_type).join('/')}"
    end
    # assign bucket ID
    set_bucket_id(workspace['bucketName'], type: workspace_type)
  end

  # handler to create a workspace for a study, either user-facing or internal
  def create_terra_workspace(type = :study)
    set_internal_workspace_name if type == :internal
    ws_namespace, ws_name = workspace_attrs(type)
    workspace_client(ws_namespace).create_workspace(ws_namespace, ws_name)
  end

  # assign all workspace-related acls to allow access
  # internal buckets grant read access to users for visualization purposes, write access for admin QA
  def assign_workspace_acls!(type = :study)
    ws_namespace, ws_name = workspace_attrs(type)
    ws_identifier = "#{ws_namespace}/#{ws_name}"
    sa_access = set_service_account_permissions(type)
    unless sa_access
      Rails.logger.info "Unable to set service account permissions for #{ws_identifier}"
      return false
    end

    Rails.logger.info "Setting workspaces acls for #{ws_identifier}"
    if type == :study
      # don't change ACL for study owner on existing workspace in their own billing project
      grant_user_write = use_existing_workspace && ws_namespace != FireCloudClient::PORTAL_NAMESPACE
      acls = grant_user_write ? [[user.email, 'WRITER']] : []
      study_shares.where(:permission.ne => 'Reviewer').each do |share|
        acls << [share.email, StudyShare::FIRECLOUD_ACL_MAP[share.permission]]
      end
      acls.each do |acl_info|
        email, permission = *acl_info
        compute_permission = permission == 'WRITER' && !FireCloudClient::COMPUTE_DENYLIST.include?(ws_namespace)
        assign_acl!(type:, email:, permission:, compute_permission:)
      end
    else
      admin_internal_group = AdminConfiguration.find_or_create_admin_internal_group!
      assign_acl!(type:, email: admin_internal_group['groupEmail'], permission: 'WRITER')
      readers = [user.email]
      readers += study_shares.non_reviewers
      readers.each do |email|
        assign_acl!(type:, email:, permission: 'READER', share_permission: false)
      end
    end
    Rails.logger.info "Workspace acls for #{ws_identifier} configured successfully"
    true
  end

  # assign an individual workspace acl
  def assign_acl!(type: :study, email:, permission:, share_permission: true, compute_permission: false)
    ws_namespace, ws_name = workspace_attrs(type)
    client = workspace_client(ws_namespace)
    acl = client.create_workspace_acl(email, permission, share_permission, compute_permission)
    client.update_workspace_acl(ws_namespace, ws_name, acl)
  end

  # automatically create associated cloud resources, such as Terra workspaces & buckets
  def initialize_with_new_workspace
    Rails.logger.info "Creating associated Terra workspaces for '#{name}'"
    validate_name_and_url
    unless billing_project_ok?
      errors.add(:firecloud_project, ' is not a project you are a member of.  Please choose another project.')
    end

    unless self.errors.any?
      begin
        create_and_validate_workspace(:study)
      rescue => e
        ErrorTracker.report_exception(e, user, self)
        # delete workspace on any fail as this amounts to a validation fail
        Rails.logger.info "Error creating Terra workspace: #{e.message}"
        # delete Terra workspace unless error is 409 Conflict (workspace already taken)
        if e.message.include?("Workspace #{firecloud_project}/#{firecloud_workspace} already exists")
          errors.add(:firecloud_workspace, ' - there is already an existing workspace using this name.  Please choose another name for your study.')
          errors.add(:name, ' - you must choose a different name for your study.')
          self.firecloud_workspace = nil
        else
          # clean up user workspace, if needed
          client = workspace_client(firecloud_project)
          if client.workspace_exists?(firecloud_project, firecloud_workspace)
            client.delete_workspace(irecloud_project, firecloud_workspace)
          end
          error_message = ApplicationController.firecloud_client.parse_error_message(e)
          errors.add(:firecloud_workspace, " creation failed: #{error_message}")
        end
        false
      end
    end
  end

  # validator to use existing FireCloud workspace
  def initialize_with_existing_workspace
    Rails.logger.info "Validating Terra workspace: #{firecloud_workspace} for '#{name}'"
    validate_name_and_url
    if Study.where(firecloud_workspace:).exists?
      errors.add(:firecloud_workspace, ': The workspace you provided is already in use by another study.  Please use another workspace.')
      return false
    end

    unless billing_project_ok?
      errors.add(:firecloud_project, ' is not a project you are a member of.  Please choose another project.')
    end

    unless self.errors.any?
      begin
        workspace = ApplicationController.firecloud_client.get_workspace(firecloud_project, firecloud_workspace)
        auth_domain = workspace['workspace']['authorizationDomain']
        unless auth_domain.empty?
          errors.add(:firecloud_workspace, ': The workspace you provided is restricted.  We currently do not allow use of restricted workspaces.  Please use another workspace.')
          return false
        end
        # ensure user has enough permission to use existing workspace
        unless user_has_workspace_access?
          errors.add(:firecloud_workspace, ': You do not have write permission for the workspace you provided.  Please use another workspace.')
          return false
        end
        acls_assigned = assign_workspace_acls!(workspace_type)
        if !acls_assigned
          errors.add(:firecloud_workspace, ": We encountered an error when attempting to set workspace permissions.  Please try again, or chose a different project.")
        else
          Rails.logger.info "'#{name}' acls ok for user workspace #{workspace_attrs.join('/')}"
        end
        # assign bucket ID
        set_bucket_id(workspace['bucketName'])
      rescue => e
        ErrorTracker.report_exception(e, self.user, self)
        # delete workspace on any fail as this amounts to a validation fail
        Rails.logger.info "#{Time.zone.now}: Error assigning workspace: #{e.message}"
        error_message = ApplicationController.firecloud_client.parse_error_message(e)
        errors.add(:firecloud_workspace, " assignment failed: #{error_message}; Please check the workspace in question and try again.")
        return false
      end
    end
  end

  # create internal workspace for holding SCP internal data, like visualization assets or parse logs
  def create_internal_workspace
    begin
      create_and_validate_workspace(:internal)
    rescue => e
      clean_up_workspaces
      # remove StudyAccession entry to free it up for re-use
      # this should ONLY ever be done here as an accession was just assigned but never used
      StudyAccession.find_by(study_id: id, accession:)&.delete
      ErrorTracker.report_exception(e, user, self)
      # delete workspace on any fail as this amounts to a validation fail
      Rails.logger.info "Error creating Terra internal workspace: #{e.message}"
      error_message = ApplicationController.firecloud_client.parse_error_message(e)
      errors.add(:internal_workspace, " creation failed: #{error_message}, please try again")
      false
    end
  end

  def clean_up_workspaces
    [:study, :internal].each do |workspace_type|
      # don't delete existing workspace
      next if workspace_type == :study && use_existing_workspace

      ws_namespace, ws_name = workspace_attrs(workspace_type)
      client = workspace_client(ws_namespace)
      if client.workspace_exists?(ws_namespace, ws_name)
        client.delete_workspace(ws_namespace, ws_name)
      end
    end
  end

  # sub-validation used on create
  def validate_name_and_url
    # check name and url_safe_name first and set validation error
    if self.name.blank? || self.name.nil?
      errors.add(:name, " cannot be blank - please provide a name for your study.")
    end
    if Study.where(name: self.name).any?
      errors.add(:name, ": #{self.name} has already been taken.  Please choose another name.")
    end
    if Study.where(url_safe_name: self.url_safe_name).any?
      errors.add(:url_safe_name, ": The name you provided (#{self.name}) tried to create a public URL (#{self.url_safe_name}) that is already assigned.  Please rename your study to a different value.")
    end
  end

  ###
  #
  # CUSTOM CALLBACKS
  #
  ###

  # remove data directory on delete
  def remove_data_dir
    if Dir.exist?(self.data_store_path)
      FileUtils.rm_rf(self.data_store_path)
    end
  end

  # set permissions on workspaces to workspace owner Google group for service account
  # this reduces the number of groups the SA is a member of to lower burden on quota (2000 direct memberships)
  def set_service_account_permissions(type = :study)
    ws_namespace, ws_name = workspace_attrs(type)
    Rails.logger.info "Checking service account permissions for #{ws_namespace}/#{ws_name}"
    client = workspace_client(ws_namespace)
    begin
      sa_owner_group = AdminConfiguration.find_or_create_ws_user_group!
      group_email = sa_owner_group['groupEmail']
      acl = client.create_workspace_acl(group_email, 'OWNER', true, false)
      client.update_workspace_acl(ws_namespace, ws_name, acl)
      updated = client.get_workspace_acl(ws_namespace, ws_name)
      return updated['acl'][group_email]['accessLevel'] == 'OWNER'
    rescue RestClient::Exception => e
      ErrorTracker.report_exception(e, self.user, { firecloud_project: ws_namespace})
      Rails.logger.error "Unable to add portal service account to #{ws_namespace}/#{ws_name}: #{e.message}"
      false
    end
  end

  def strip_unsafe_characters_from_description
    self.description = self.description.to_s.gsub(ValidationTools::SCRIPT_TAG_REGEX, '')
  end

  # prevent editing firecloud project or workspace on edit
  def prevent_firecloud_attribute_changes
    if self.persisted? && !self.queued_for_deletion # skip this validation if we're queueing for deletion
      if self.firecloud_project_changed?
        errors.add(:firecloud_project, 'cannot be changed once initialized.')
      end
      if self.firecloud_workspace_changed?
        errors.add(:firecloud_workspace, 'cannot be changed once initialized.')
      end
    end
  end

  # delete all records that are associate with this study before invoking :destroy to speed up performance
  # only pertains to "parsed" data as other records will be cleaned up via callbacks
  # provides much better performance to study.destroy while ensuring cleanup consistency
  def ensure_cascade_on_associations
    # ensure all BQ data is cleaned up first
    self.delete_convention_data
    self.study_files.each do |file|
      DataArray.where(study_id: self.id, study_file_id: file.id).delete_all
    end
    Gene.where(study_id: self.id).delete_all
    CellMetadatum.where(study_id: self.id).delete_all
    PrecomputedScore.where(study_id: self.id).delete_all
    ClusterGroup.where(study_id: self.id).delete_all
    StudyFile.where(study_id: self.id).delete_all
    DirectoryListing.where(study_id: self.id).delete_all
    UserAnnotation.where(study_id: self.id).delete_all
    UserAnnotationShare.where(study_id: self.id).delete_all
    UserDataArray.where(study_id: self.id).delete_all
    AnalysisMetadatum.where(study_id: self.id).delete_all
    StudyFileBundle.where(study_id: self.id).delete_all
  end

  # we aim to track all fields except fields that are auto-updated.
  # modifier is set to nil because unfortunately we can't easily track the user who made certain changes
  # the gem (Mongoid::Userstamp) mongoid-history recommends for doing that (which auto-sets the current_user as the modifier)
  # does not seem to work with the latest versions of mongoid
  track_history except: [:created_at, :updated_at, :view_count, :cell_count, :gene_count, :data_dir], modifier_field: nil
end
