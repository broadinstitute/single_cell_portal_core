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

  has_many :differential_expression_results, dependent: :delete_all

  # field definitions
  field :name, type: String
  field :embargo, type: Date
  field :url_safe_name, type: String
  field :accession, type: String
  field :description, type: String
  field :firecloud_workspace, type: String
  field :firecloud_project, type: String, default: FireCloudClient::PORTAL_NAMESPACE
  field :bucket_id, type: String
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
    property :bucket_id do
      key :type, :string
      key :description, 'GCS Bucket name where uploaded files are stored'
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

  validates_format_of :firecloud_workspace, :firecloud_project,
                      with: ValidationTools::ALPHANUMERIC_SPACE_DASH, message: ValidationTools::ALPHANUMERIC_SPACE_DASH_ERROR

  validates_format_of :data_dir, :bucket_id, :url_safe_name,
                      with: ValidationTools::ALPHANUMERIC_DASH, message: ValidationTools::ALPHANUMERIC_DASH_ERROR

  # update validators
  validates_uniqueness_of :name, on: :update, message: ": %{value} has already been taken.  Please choose another name."
  validates_presence_of   :name, on: :update
  validates_uniqueness_of :url_safe_name, on: :update, message: ": The name you provided tried to create a public URL (%{value}) that is already assigned.  Please rename your study to a different value."
  validate :prevent_firecloud_attribute_changes, on: :update
  validates_presence_of :firecloud_project, :firecloud_workspace
  # callbacks
  before_validation :set_url_safe_name
  before_validation :set_data_dir, :set_firecloud_workspace_name, on: :create
  after_validation  :assign_accession, on: :create
  # before_save       :verify_default_options
  after_create      :make_data_dir, :set_default_participant
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
      group_shares = []
      if user.registered_for_firecloud && (user.refresh_token.present? || user.api_access_token.present?)
        user_client = FireCloudClient.new(user, FireCloudClient::PORTAL_NAMESPACE)
        user_groups = user_client.get_user_groups.map {|g| g['groupEmail']}
        group_shares = StudyShare.where(:email.in => user_groups).map(&:study).select {|s| !s.queued_for_deletion }.map(&:id)
      end
      intersection = public + owned + shares + group_shares
      # return Mongoid criterion object to use with pagination
      Study.in(:_id => intersection)
    end
  end

  # return all studies either owned by or shared with a given user as a Mongoid criterion
  def self.accessible(user)
    if user.admin?
      self.where(queued_for_deletion: false)
    else
      owned = self.where(user_id: user._id, queued_for_deletion: false).map(&:_id)
      shares = StudyShare.where(email: /#{user.email}/i).map(&:study).select {|s| !s.queued_for_deletion }.map(&:_id)
      group_shares = []
      if user.registered_for_firecloud
        user_client = FireCloudClient.new(user, FireCloudClient::PORTAL_NAMESPACE)
        user_groups = user_client.get_user_groups.map {|g| g['groupEmail']}
        group_shares = StudyShare.where(:email.in => user_groups).map(&:study).select {|s| !s.queued_for_deletion }.map(&:id)
      end
      intersection = owned + shares + group_shares
      Study.in(:_id => intersection)
    end
  end

  # check if a give use can edit study
  def can_edit?(user)
    if user.nil?
      false
    else
      if self.admins.map(&:downcase).include?(user.email.downcase)
        return true
      else
        self.user_in_group_share?(user, 'Edit')
      end
    end
  end

  # check if a given user can view study by share (does not take public into account - use Study.viewable(user) instead)
  def can_view?(user)
    if user.nil?
      false
    else
      # use if/elsif with explicit returns to ensure skipping downstream calls
      if self.study_shares.can_view.map(&:downcase).include?(user.email.downcase)
        return true
      elsif self.can_edit?(user)
        return true
      else
        return self.user_in_group_share?(user, 'View', 'Reviewer')
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
      # get user's FC groups
      if user.access_token.present?
        client = FireCloudClient.new(user, FireCloudClient::PORTAL_NAMESPACE)
      elsif user.api_access_token.present?
        client = FireCloudClient.new
        client.access_token[:access_token] = user.api_access_token
      else
        false
      end
      begin
        user_groups = client.get_user_groups.map {|g| g['groupEmail']}
        # use native array intersection to determine if any of the user's groups have been shared with this study at the correct permission
        (user_groups & group_shares).any?
      rescue => e
        ErrorTracker.report_exception(e, user, { user_groups: user_groups, study: self.attributes.to_h})
        Rails.logger.error "Unable to retrieve user groups for #{user.email}: #{e.class.name} -- #{e.message}"
        false
      end
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
    self.has_bam_files? || self.has_analysis_outputs?('infercnv', 'ideogram.js')
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

  def has_image_files?
    study_files.by_type('Image').any?
  end

  # check if study has any files that can be streamed from the bucket for visualization
  # this includes BAM, inferCNV Ideogram annotations, Image files, and DE files
  #
  # TODO (SCP-4336):
  # This is currently only used for getting auth tokens.  Consider incorporating this
  # into existing endpoints, or perhaps a new endpoint, where the token is returned as part
  # of the API response.
  def has_streamable_files(user)
    has_bam_files? ||
    has_analysis_outputs?('infercnv', 'ideogram.js') ||
    has_image_files? ||
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

  # helper to generate a URL to a study's FireCloud workspace
  def workspace_url
    "https://app.terra.bio/#workspaces/#{self.firecloud_project}/#{self.firecloud_workspace}"
  end

  # helper to generate an HTTPS URL to a study's GCP bucket
  def google_bucket_url
    "https://accounts.google.com/AccountChooser?continue=https://console.cloud.google.com/storage/browser/#{self.bucket_id}"
  end

  # helper to generate a GS URL to a study's GCP bucket
  def gs_url
    "gs://#{self.bucket_id}"
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

  def has_bam_files?
    self.study_files.by_type('BAM').any?
  end

  # Get a list of BAM file objects where each object has a URL for the BAM
  # itself and index URL for its matching BAI file.
  def get_bam_files

    bam_files = self.study_files.by_type('BAM')
    bams = []

    bam_files.each do |bam_file|
      next unless bam_file.has_completed_bundle?

      bams << {
          'name' => bam_file.name,
          'url' => bam_file.api_url,
          'indexUrl' => bam_file.study_file_bundle.bundled_file_by_type('BAM Index')&.api_url,
          'genomeAssembly' => bam_file.genome_assembly_name,
          'genomeAnnotation' => bam_file.genome_annotation
      }
    end
    bams
  end

  def get_genome_annotations_by_assembly
    genome_annotations = {}
    bam_files = self.study_files.by_type('BAM')
    bam_files.each do |bam_file|
      assembly = bam_file.genome_assembly_name
      if !genome_annotations.key?(assembly)
        genome_annotations[assembly] = {}
      end
      genome_annotation = bam_file.genome_annotation
      if !genome_annotations[assembly].key?(genome_annotation)

        # Only handle one annotation per genome assembly for now;
        # enhance to support multiple annotations when UI supports it
        genome_annotations[assembly]['genome_annotations'] = {
          'name': genome_annotation,
          'url': bam_file.genome_annotation_link,
          'indexUrl': bam_file.genome_annotation_index_link
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
      Rails.logger.info "#{Time.zone.now}: Uploading #{file.bucket_location}:#{file.id} to FireCloud workspace: #{self.firecloud_workspace}"
      file_location = file.local_location.to_s
      # determine if file needs to be compressed
      first_two_bytes = File.open(file_location).read(2)
      gzip_signature = StudyFile::GZIP_MAGIC_NUMBER # per IETF
      file_is_gzipped = (first_two_bytes == gzip_signature)

      opts = {}
      if file_is_gzipped or file.upload_file_name.last(4) == '.bam' or file.upload_file_name.last(5) == '.cram'
        # log that file is already compressed
        Rails.logger.info "#{Time.zone.now}: #{file.upload_file_name}:#{file.id} is already compressed, direct uploading"
      else
        Rails.logger.info "#{Time.zone.now}: Performing gzip on #{file.upload_file_name}:#{file.id}"
        # Compress all uncompressed files before upload.
        # This saves time on upload and download, and money on egress and storage.
        gzip_filepath = file_location + '.tmp.gz'
        Zlib::GzipWriter.open(gzip_filepath) do |gz|
          File.open(file_location, 'rb').each do |line|
            gz.write line
          end
          gz.close
        end
        File.rename gzip_filepath, file_location
        opts.merge!(content_encoding: 'gzip')
      end
      remote_file = ApplicationController.firecloud_client.execute_gcloud_method(:create_workspace_file, 0, self.bucket_id, file.upload.path,
                                                                 file.bucket_location, opts)
      # store generation tag to know whether a file has been updated in GCP
      Rails.logger.info "#{Time.zone.now}: Updating #{file.bucket_location}:#{file.id} with generation tag: #{remote_file.generation} after successful upload"
      file.update(generation: remote_file.generation)
      Rails.logger.info "#{Time.zone.now}: Upload of #{file.bucket_location}:#{file.id} complete, scheduling cleanup job"
      # schedule the upload cleanup job to run in two minutes
      run_at = 2.minutes.from_now
      Delayed::Job.enqueue(UploadCleanupJob.new(file.study, file, 0), run_at: run_at)
      Rails.logger.info "#{Time.zone.now}: cleanup job for #{file.bucket_location}:#{file.id} scheduled for #{run_at}"
    rescue => e
      ErrorTracker.report_exception(e, user, self, file)
      Rails.logger.error "Unable to upload '#{file.bucket_location}:#{file.id} to study bucket #{self.bucket_id}; #{e.message}"
      # notify admin of failure so they can push the file and relauch parse
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
      rescue RuntimeError => e
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
      ApplicationController.firecloud_client.delete_workspace(firecloud_project, firecloud_workspace) unless detached
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

  ###
  #
  # CUSTOM VALIDATIONS
  #
  ###

  # automatically create a FireCloud workspace on study creation after validating name & url_safe_name
  # will raise validation errors if creation, bucket or ACL assignment fail for any reason and deletes workspace on validation fail
  def initialize_with_new_workspace
    Rails.logger.info "#{Time.zone.now}: Study: #{self.name} creating FireCloud workspace"
    validate_name_and_url

    # check if project is valid to use
    if self.firecloud_project != FireCloudClient::PORTAL_NAMESPACE
      client = FireCloudClient.new(self.user, self.firecloud_project)
      projects = client.get_billing_projects.map {|project| project['projectName']}
      unless projects.include?(self.firecloud_project)
        errors.add(:firecloud_project, ' is not a project you are a member of.  Please choose another project.')
      end
    end

    unless self.errors.any?
      begin
        # create workspace
        if self.firecloud_project == FireCloudClient::PORTAL_NAMESPACE
          workspace = ApplicationController.firecloud_client.create_workspace(self.firecloud_project, self.firecloud_workspace, true)
        else
          workspace = client.create_workspace(self.firecloud_project, self.firecloud_workspace)
        end
        Rails.logger.info "#{Time.zone.now}: Study: #{self.name} FireCloud workspace creation successful"

        # wait until after workspace creation to set service account permissions
        Rails.logger.info "#{Time.zone.now}: Study: #{self.name} checking service account permissions"
        has_access = set_service_account_permissions
        if !has_access
          errors.add(:firecloud_workspace, ": We encountered an error when attempting to set service account permissions.  Please try again, or chose a different project.")
        else
          Rails.logger.info "#{Time.zone.now}: Study: #{self.name} service account permissions ok"
        end

        ws_name = workspace['name']
        # validate creation
        unless ws_name == self.firecloud_workspace
          # delete workspace on validation fail
          ApplicationController.firecloud_client.delete_workspace(self.firecloud_project, self.firecloud_workspace)
          errors.add(:firecloud_workspace, ' was not created properly (workspace name did not match or was not created).  Please try again later.')
          return false
        end
        Rails.logger.info "#{Time.zone.now}: Study: #{self.name} FireCloud workspace validation successful"
        # set bucket_id
        bucket = workspace['bucketName']
        self.bucket_id = bucket
        if self.bucket_id.nil?
          # delete workspace on validation fail
          ApplicationController.firecloud_client.delete_workspace(self.firecloud_project, self.firecloud_workspace)
          errors.add(:firecloud_workspace, ' was not created properly (storage bucket was not set).  Please try again later.')
          return false
        end
        Rails.logger.info "#{Time.zone.now}: Study: #{self.name} FireCloud bucket assignment successful"

        # if user has no project acls, then we set specific workspace-level acls
        if self.firecloud_project == FireCloudClient::PORTAL_NAMESPACE
          # set workspace acl
          study_owner = self.user.email
          workspace_permission = 'WRITER'
          can_compute = true
          # if study project is in the compute denylist, revoke compute permission
          if Rails.env.production? && FireCloudClient::COMPUTE_DENYLIST.include?(self.firecloud_project)
            can_compute = false
          end
          acl = ApplicationController.firecloud_client.create_workspace_acl(study_owner, workspace_permission, true, can_compute)
          ApplicationController.firecloud_client.update_workspace_acl(self.firecloud_project, self.firecloud_workspace, acl)
          # validate acl
          ws_acl = ApplicationController.firecloud_client.get_workspace_acl(self.firecloud_project, ws_name)
          unless ws_acl['acl'][study_owner]['accessLevel'] == workspace_permission && ws_acl['acl'][study_owner]['canCompute'] == can_compute
            # delete workspace on validation fail
            ApplicationController.firecloud_client.delete_workspace(self.firecloud_project, self.firecloud_workspace)
            errors.add(:firecloud_workspace, ' was not created properly (permissions do not match).  Please try again later.')
            return false
          end
        end
        Rails.logger.info "#{Time.zone.now}: Study: #{self.name} FireCloud workspace acl assignment successful"
        if self.study_shares.any?
          Rails.logger.info "#{Time.zone.now}: Study: #{self.name} FireCloud workspace acl assignment for shares starting"
          self.study_shares.each do |share|
            begin
              acl = ApplicationController.firecloud_client.create_workspace_acl(share.email, StudyShare::FIRECLOUD_ACL_MAP[share.permission], true, false)
              ApplicationController.firecloud_client.update_workspace_acl(self.firecloud_project, self.firecloud_workspace, acl)
              Rails.logger.info "#{Time.zone.now}: Study: #{self.name} FireCloud workspace acl assignment for shares #{share.email} successful"
            rescue RuntimeError => e
              ErrorTracker.report_exception(e, user, self, acl)
              errors.add(:study_shares, "Could not create a share for #{share.email} to workspace #{self.firecloud_workspace} due to: #{e.message}")
              return false
            end
          end
        end

      rescue => e
        ErrorTracker.report_exception(e, user, self)
        # delete workspace on any fail as this amounts to a validation fail
        Rails.logger.info "#{Time.zone.now}: Error creating workspace: #{e.message}"
        # delete firecloud workspace unless error is 409 Conflict (workspace already taken)
        if e.message.include?("Workspace #{self.firecloud_project}/#{self.firecloud_workspace} already exists")
          errors.add(:firecloud_workspace, ' - there is already an existing workspace using this name.  Please choose another name for your study.')
          errors.add(:name, ' - you must choose a different name for your study.')
          self.firecloud_workspace = nil
        else
          ApplicationController.firecloud_client.delete_workspace(self.firecloud_project, self.firecloud_workspace)
          errors.add(:firecloud_workspace, " creation failed: #{e.message}; Please try again.")
        end
        return false
      end
    end
  end

  # validator to use existing FireCloud workspace
  def initialize_with_existing_workspace
    Rails.logger.info "#{Time.zone.now}: Study: #{self.name} using FireCloud workspace: #{self.firecloud_workspace}"
    validate_name_and_url
    # check if workspace is already being used
    if Study.where(firecloud_workspace: self.firecloud_workspace).exists?
      errors.add(:firecloud_workspace, ': The workspace you provided is already in use by another study.  Please use another workspace.')
      return false
    end

    # check if project is valid to use
    if self.firecloud_project != FireCloudClient::PORTAL_NAMESPACE
      client = FireCloudClient.new(self.user, self.firecloud_project)
      projects = client.get_billing_projects.map {|project| project['projectName']}
      unless projects.include?(self.firecloud_project)
        errors.add(:firecloud_project, ' is not a project you are a member of.  Please choose another project.')
      end
    end

    Rails.logger.info "#{Time.zone.now}: Study: #{self.name} checking service account permissions"
    has_access = set_service_account_permissions
    if !has_access
      errors.add(:firecloud_workspace, ": We encountered an error when attempting to set service account permissions.  Please try again, or chose a different project.")
    else
      Rails.logger.info "#{Time.zone.now}: Study: #{self.name} service account permissions ok"
    end
    unless self.errors.any?
      begin
        workspace = ApplicationController.firecloud_client.get_workspace(self.firecloud_project, self.firecloud_workspace)
        study_owner = self.user.email
        # set acls if using default project
        if self.firecloud_project == FireCloudClient::PORTAL_NAMESPACE
          workspace_permission = 'WRITER'
          can_compute = true
          # if study project is in the compute denylist, revoke compute permission
          if Rails.env.production? && FireCloudClient::COMPUTE_DENYLIST.include?(self.firecloud_project)
            can_compute = false
            Rails.logger.info "#{Time.zone.now}: Study: #{self.name} removing compute permissions"
            compute_acl = ApplicationController.firecloud_client.create_workspace_acl(self.user.email, workspace_permission, true, can_compute)
            ApplicationController.firecloud_client.update_workspace_acl(self.firecloud_project, self.firecloud_workspace, compute_acl)
          end
          acl = ApplicationController.firecloud_client.get_workspace_acl(self.firecloud_project, self.firecloud_workspace)
          # first check workspace authorization domain
          auth_domain = workspace['workspace']['authorizationDomain']
          unless auth_domain.empty?
            errors.add(:firecloud_workspace, ': The workspace you provided is restricted.  We currently do not allow use of restricted workspaces.  Please use another workspace.')
            return false
          end
          # check permissions, falling back to project-level permissions if needed
          is_project_owner = false
          if acl['acl'][study_owner].nil? || acl['acl'][study_owner]['accessLevel'] == 'READER'
            Rails.logger.info "checking project-level permissions for user_id:#{self.user.id} in #{self.firecloud_project}"
            is_project_owner = self.user.is_billing_project_owner?(self.firecloud_project)
            unless is_project_owner
              errors.add(:firecloud_workspace, ': You do not have write permission for the workspace you provided.  Please use another workspace.')
              return false
            end
            Rails.logger.info "project-level permissions check successful"
          end
          # check compute permissions (only if not project owner, as compute is inherited and not present at the workspace level)
          if !is_project_owner && acl['acl'][study_owner]['canCompute'] != can_compute
            errors.add(:firecloud_workspace, ': There was an error setting the permissions on your workspace (compute permissions were not set correctly).  Please try again.')
            return false
          end
          Rails.logger.info "#{Time.zone.now}: Study: #{self.name} FireCloud workspace acl check successful"
          # set bucket_id, it is nested lower since we had to get an existing workspace
        end

        bucket = workspace['workspace']['bucketName']
        self.bucket_id = bucket
        if self.bucket_id.nil?
          # delete workspace on validation fail
          errors.add(:firecloud_workspace, ' was not created properly (storage bucket was not set).  Please try again later.')
          return false
        end
        Rails.logger.info "#{Time.zone.now}: Study: #{self.name} FireCloud bucket assignment successful"
        if self.study_shares.any?
          Rails.logger.info "#{Time.zone.now}: Study: #{self.name} FireCloud workspace acl assignment for shares starting"
          self.study_shares.each do |share|
            begin
              acl = ApplicationController.firecloud_client.create_workspace_acl(share.email, StudyShare::FIRECLOUD_ACL_MAP[share.permission], true, false)
              ApplicationController.firecloud_client.update_workspace_acl(self.firecloud_project, self.firecloud_workspace, acl)
              Rails.logger.info "#{Time.zone.now}: Study: #{self.name} FireCloud workspace acl assignment for shares #{share.email} successful"
            rescue RuntimeError => e
              ErrorTracker.report_exception(e, user, self, acl)
              errors.add(:study_shares, "Could not create a share for #{share.email} to workspace #{self.firecloud_workspace} due to: #{e.message}")
              return false
            end
          end
        end
      rescue => e
        ErrorTracker.report_exception(e, self.user, self)
        # delete workspace on any fail as this amounts to a validation fail
        Rails.logger.info "#{Time.zone.now}: Error assigning workspace: #{e.message}"
        errors.add(:firecloud_workspace, " assignment failed: #{e.message}; Please check the workspace in question and try again.")
        return false
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
  def set_service_account_permissions
    begin
      sa_owner_group = AdminConfiguration.find_or_create_ws_user_group!
      if self.firecloud_project == FireCloudClient::PORTAL_NAMESPACE
        client = ApplicationController.firecloud_client
      else
        client = FireCloudClient.new(self.user, self.firecloud_project)
      end
      group_email = sa_owner_group['groupEmail']
      acl = client.create_workspace_acl(group_email, 'OWNER', true, false)
      client.update_workspace_acl(self.firecloud_project, self.firecloud_workspace, acl)
      updated = client.get_workspace_acl(self.firecloud_project, self.firecloud_workspace)
      return updated['acl'][group_email]['accessLevel'] == 'OWNER'
    rescue RuntimeError => e
      ErrorTracker.report_exception(e, self.user, { firecloud_project: self.firecloud_workspace})
      Rails.logger.error "Unable to add portal service account to #{self.firecloud_workspace}: #{e.message}"
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
