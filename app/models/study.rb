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
  extend ErrorTracker
  include Swagger::Blocks

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

  # instantiate one FireCloudClient to avoid creating too many tokens
  @@firecloud_client = FireCloudClient.new
  @@read_only_client = ENV['READ_ONLY_SERVICE_ACCOUNT_KEY'].present? ? FireCloudClient.new(nil, FireCloudClient::PORTAL_NAMESPACE, File.absolute_path(ENV['READ_ONLY_SERVICE_ACCOUNT_KEY'])) : nil

  # getter for FireCloudClient instance
  def self.firecloud_client
    @@firecloud_client
  end

  def self.read_only_firecloud_client
    @@read_only_client
  end

  # method to renew firecloud client (forces new access token for API and reinitializes storage driver)
  def self.refresh_firecloud_client
    begin
      @@firecloud_client = FireCloudClient.new
      true
    rescue => e
      ErrorTracker.report_exception(e, nil, self.firecloud_client.attributes)
      Rails.logger.error "#{Time.zone.now}: unable to refresh FireCloud client: #{e.message}"
      e.message
    end
  end

  ###
  #
  # SETTINGS, ASSOCIATIONS AND SCOPES
  #
  ###

  # pagination
  def self.per_page
    5
  end

  # associations and scopes
  belongs_to :user
  belongs_to :branding_group, optional: true
  has_many :study_files, dependent: :delete do
    def by_type(file_type)
      if file_type.is_a?(Array)
        where(queued_for_deletion: false, :file_type.in => file_type).to_a
      else
        where(queued_for_deletion: false, file_type: file_type).to_a
      end
    end

    def non_primary_data
      where(queued_for_deletion: false).not_in(file_type: StudyFile::PRIMARY_DATA_TYPES).to_a
    end

    def primary_data
      where(queued_for_deletion: false).in(file_type: StudyFile::PRIMARY_DATA_TYPES).to_a
    end

    def valid
      where(queued_for_deletion: false, :generation.ne => nil).to_a
    end
  end

  has_many :study_file_bundles, dependent: :destroy do
    def by_type(file_type)
      if file_type.is_a?(Array)
        where(:bundle_type.in => file_type)
      else
        where(bundle_type: file_type)
      end
    end
  end

  has_many :genes, dependent: :delete do
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

  has_many :precomputed_scores, dependent: :delete do
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
      if Study.read_only_firecloud_client.present?
        where(:email.not => /Study.read_only_firecloud_client.issuer/).map(&:email)
      else
        all.to_a.map(&:email)
      end
    end
  end

  has_many :cluster_groups, dependent: :delete do
    def by_name(name)
      find_by(name: name)
    end
  end

  has_many :data_arrays, as: :linear_data, dependent: :delete do
    def by_name_and_type(name, type)
      where(name: name, array_type: type).order_by(&:array_index)
    end
  end

  has_many :cell_metadata, dependent: :delete do
    def by_name_and_type(name, type)
      where(name: name, annotation_type: type).first
    end
  end

  has_many :directory_listings, dependent: :delete do
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
  has_many :user_annotations, dependent: :delete
  has_many :user_data_arrays, dependent: :delete

  # HCA metadata object
  has_many :analysis_metadata, dependent: :delete

  # Study Accession
  has_one :study_accession

  # External Resource links
  has_many :external_resources, as: :resource_links

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

  accepts_nested_attributes_for :study_files, allow_destroy: true
  accepts_nested_attributes_for :study_shares, allow_destroy: true, reject_if: proc { |attributes| attributes['email'].blank? }
  accepts_nested_attributes_for :external_resources, allow_destroy: true

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
      key :description, 'HTML description blob for Study'
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
            key :description, 'HTML description blob for Study'
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
      key :description, 'Indication this study was whitelisted by a preset search'
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
  validate :initialize_with_new_workspace, on: :create, if: Proc.new {|study| !study.use_existing_workspace}
  validate :initialize_with_existing_workspace, on: :create, if: Proc.new {|study| study.use_existing_workspace}

  # populate specific errors for study shares since they share the same form
  validate do |study|
    study.study_shares.each do |study_share|
      next if study_share.valid?
      study_share.errors.full_messages.each do |msg|
        errors.add(:base, "Share Error - #{msg}")
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
      shares = StudyShare.where(email: user.email, permission: 'Edit').map(&:study).select {|s| !s.queued_for_deletion }
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
      shares = StudyShare.where(email: user.email).map(&:study).select {|s| !s.queued_for_deletion }.map(&:id)
      group_shares = []
      if user.registered_for_firecloud
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
      shares = StudyShare.where(email: user.email).map(&:study).select {|s| !s.queued_for_deletion }.map(&:_id)
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
      if self.admins.include?(user.email)
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
      if self.study_shares.can_view.include?(user.email)
        return true
      elsif self.can_edit?(user)
        return true
      else
        self.user_in_group_share?(user, 'View', 'Reviewer')
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
      elsif self.study_shares.non_reviewers.include?(user.email)
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
      if Study.firecloud_client.services_available?(FireCloudClient::SAM_SERVICE, FireCloudClient::RAWLS_SERVICE, FireCloudClient::AGORA_SERVICE)
        begin
          workspace_acl = Study.firecloud_client.get_workspace_acl(self.firecloud_project, self.firecloud_workspace)
          if workspace_acl['acl'][user.email].nil?
            # check if user has project-level permissions
            user_client = FireCloudClient.new(user, self.firecloud_project)
            projects = user_client.get_billing_projects
            # billing project users can only create workspaces, so unless user is an owner, user cannot compute
            projects.detect {|project| project['projectName'] == self.firecloud_project && project['role'] == 'Owner'}.present?
          else
            workspace_acl['acl'][user.email]['canCompute']
          end
        rescue => e
          ErrorTracker.report_exception(e, user, {study: self.attributes.to_h})
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
    if user.registered_for_firecloud && Study.firecloud_client.services_available?(FireCloudClient::SAM_SERVICE, FireCloudClient::RAWLS_SERVICE, FireCloudClient::THURLOE_SERVICE)
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
        ErrorTracker.report_exception(e, user, {user_groups: user_groups, study: self.attributes.to_h})
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

  # check if study is still under embargo or whether given user can bypass embargo
  def embargoed?(user)
    if user.nil?
      self.check_embargo?
    else
      # must not be viewable by current user & embargoed to be true
      !self.can_view?(user) && self.check_embargo?
    end
  end

  # helper method to check embargo status
  def check_embargo?
    self.embargo.nil? || self.embargo.blank? ? false : Date.today <= self.embargo
  end

  # label for study visibility
  def visibility
    self.public? ? "<span class='sc-badge bg-success text-success'>Public</span>".html_safe : "<span class='sc-badge bg-danger text-danger'>Private</span>".html_safe
  end

  # helper method to return key-value pairs of sharing permissions local to portal (not what is persisted in FireCloud)
  # primarily used when syncing study with FireCloud workspace
  def local_acl
    acl = {
        "#{self.user.email}" => (Rails.env == 'production' && FireCloudClient::COMPUTE_BLACKLIST.include?(self.firecloud_project)) ? 'Edit' : 'Owner'
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
      text_blob = "#{self.name} #{self.description}"
      score = text_blob.scan(/#{term}/i).size
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
    self.can_visualize_clusters? || self.can_visualize_genome_data?
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

  # helper to return default annotation to load, will fall back to first available annotation if no preference has been set
  # or default annotation cannot be loaded
  def default_annotation
    default_cluster = self.default_cluster
    default_annot = self.default_options[:annotation]
    # in case default has not been set
    if default_annot.nil?
      if !default_cluster.nil? && default_cluster.cell_annotations.any?
        annot = default_cluster.cell_annotations.first
        default_annot = "#{annot[:name]}--#{annot[:type]}--cluster"
      elsif self.cell_metadata.any?
        metadatum = self.cell_metadata.first
        default_annot = "#{metadatum.name}--#{metadatum.annotation_type}--study"
      else
        # annotation won't be set yet if a user is parsing metadata without clusters, or vice versa
        default_annot = nil
      end
    end
    default_annot
  end

  # helper to return default annotation type (group or numeric)
  def default_annotation_type
    if self.default_options[:annotation].nil?
      nil
    else
      # middle part of the annotation string is the type, e.g. Label--group--study
      self.default_options[:annotation].split('--')[1]
    end
  end

  # return color profile value, converting blanks to nils
  def default_color_profile
    self.default_options[:color_profile].presence
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
    gene_count = self.unique_genes
    Rails.logger.info "Setting gene count in #{self.name} to #{gene_count}"
    self.update(gene_count: gene_count)
    Rails.logger.info "Gene count set for #{self.name}"
  end

  # get all unique gene names for a study; leverage index on Gene model to improve performance
  def unique_genes
    Gene.where(study_id: self.id, :study_file_id.in => self.expression_matrix_files.map(&:id)).pluck(:name).uniq
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

  ###
  #
  # METADATA METHODS
  #
  ###

  # return an array of all single cell names in study
  def all_cells
    annot = self.study_metadata.first
    if annot.present?
      annot.cell_annotations.keys
    else
      []
    end
  end

  # return an array of all single cell names in study, will check for master list of cells or concatenate all
  # cell lists from individual expression matrices
  def all_cells_array
    vals = []
    arrays = DataArray.where(study_id: self.id, linear_data_type: 'Study', linear_data_id: self.id, name: 'All Cells').order_by(&:array_index)
    if arrays.any?
      arrays.each do |array|
        vals += array.values
      end
    else
      vals = self.all_expression_matrix_cells
    end
    vals
  end

  # return an array of all cell names that have been used in expression matrices (does not get cells from cell metadata file)
  def all_expression_matrix_cells
    vals = []
    self.expression_matrix_files.each do |file|
      arrays = DataArray.where(name: "#{file.name} Cells", array_type: 'cells', linear_data_type: 'Study',
                               linear_data_id: self.id).order_by(&:array_index)
      arrays.each do |array|
        vals += array.values
      end
    end
    vals
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

  # helper method to access all cluster definitions files
  def cluster_ordinations_files
    self.study_files.by_type('Cluster')
  end

  # helper method to access cluster definitions file by name
  def cluster_ordinations_file(name)
    self.study_files.find_by(file_type: 'Cluster', name: name)
  end

  # helper method to directly access expression matrix files
  def expression_matrix_files
    self.study_files.by_type(['Expression Matrix', 'MM Coordinate Matrix'])
  end

  # helper method to directly access expression matrix file file by name
  def expression_matrix_file(name)
    self.study_files.find_by(:file_type.in => ['Expression Matrix', 'MM Coordinate Matrix'], name: name)
  end
  # helper method to directly access metadata file
  def metadata_file
    self.study_files.by_type('Metadata').first
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
      'assembly': exp_file.genome_assembly['name'],
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
      bams << {
          'url' => bam_file.api_url,
          'indexUrl' => bam_file.bundled_files.first.api_url,
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
      Gene.where(study_id: study.id).delete_all
      study.study_files.each do |file|
        DataArray.where(study_id: study.id, study_file_id: file.id).delete_all
      end
      CellMetadatum.where(study_id: study.id).delete_all
      PrecomputedScore.where(study_id: study.id).delete_all
      ClusterGroup.where(study_id: study.id).delete_all
      StudyFile.where(study_id: study.id).delete_all
      DirectoryListing.where(study_id: study.id).delete_all
      UserAnnotation.where(study_id: study.id).delete_all
      UserAnnotationShare.where(study_id: study.id).delete_all
      UserDataArray.where(study_id: study.id).delete_all
      AnalysisMetadatum.where(study_id: study.id).delete_all
      StudyFileBundle.where(study_id: study.id).delete_all
      # now destroy study to ensure everything is removed
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

  # transform expression data from db into mtx format
  def expression_to_matrix_market(expression_file)
    puts "Generating Matrix Market coordinate (mm) file for #{self.name} expression data"
    puts 'Reading source data...'
    genes = Gene.where(study_id: self.id, study_file_id: expression_file.id)
    puts 'Assembling counts...'
    score_count = genes.size
    all_cells = self.all_cells_array
    cell_count = all_cells.size
    significant_values = score_count + cell_count + 1 # extra value is for GENE header
    score_file = File.new(self.data_store_path.to_s + "/#{expression_file.name}.tmp", 'w+')
    counter = 0
    puts 'Writing gene-level scores...'
    genes.each_with_index do |gene, gene_index|
      gene_name = gene.name
      score_file.write "#{gene_index + 2}\t1\t#{gene_name}\n"
      gene.scores.each do |cell, score|
        cell_index = all_cells.index(cell)
        score_file.write "#{gene_index + 2}\t#{cell_index + 2}\t#{score}\n"
        significant_values += 1
      end
      counter += 1
      if counter % 1000 == 0
        puts "#{counter} genes written out of #{score_count}"
      end
    end
    puts 'Finished writing scores, updating significant score count...'
    score_file.close
    output_file = File.new(self.data_store_path.to_s + "/#{expression_file.name}.mm", 'w+')
    reopened_file = File.open(self.data_store_path.to_s + "/#{expression_file.name}.tmp", 'r')
    puts 'Creating final output file and writing headers...'
    output_file.write "%%MatrixMarket matrix coordinate double symmetric\n"
    output_file.write "#{score_count + 1}\t#{cell_count + 1}\t#{significant_values}\n"
    puts 'Headers successfully written!'
    puts 'Writing cell list...'
    output_file.write "1\t1\tGENE\n"
    all_cells.each_with_index do |cell, index|
      output_file.write "1\t#{index + 2}\t#{cell}\n"
    end
    puts 'Cell list successfully written!'
    puts 'Concatenating files...'
    while !reopened_file.eof?
      output_file.write reopened_file.readline
    end
    puts 'Finished!'
    puts "Output file: #{File.absolute_path(output_file)}"
    reopened_file.close
    File.delete(reopened_file.path)
    output_file.close
  end

  # regenerate an expression matrix from database records
  def generate_dense_matrix(expression_study_file)
    puts "generating #{expression_study_file.upload_file_name} as dense expression matrix"

    # load cell arrays to create headers
    expression_file_cells = DataArray.where(study_id: self.id, linear_data_type: 'Study', linear_data_id: self.id,
                                            array_type: 'cells', study_file_id: expression_study_file.id).order(:array_index => 'asc')
    all_cells = expression_file_cells.map(&:values).flatten

    # create new file and write headers
    current_name = expression_study_file.upload_file_name
    if current_name.include?('/')
      current_name = current_name.split('/').last
    end
    new_file_name = current_name.end_with?('.txt') ? current_name : current_name + '.txt'
    if expression_study_file.upload_content_type == 'application/gzip'
      @new_expression_file = Zlib::GzipWriter.open(File.join(self.data_store_path, new_file_name))
    else
      @new_expression_file = File.new(File.join(self.data_store_path, new_file_name), 'w+')
    end
    headers = ['GENE', all_cells].flatten.join("\t")
    @new_expression_file.write headers + "\n"

    # load expression scores for requested file and write
    puts "loading expression data from #{self.name}"
    genes = Gene.where(study_id: self.id, study_file_id: expression_study_file.id)
    genes.each do |gene|
      puts "writing #{gene.name} expression values"
      @new_expression_file.write "#{gene.name}\t"
      vals = []
      scores = gene.scores
      all_cells.each do |cell|
        vals << scores[cell].to_f
      end
      @new_expression_file.write vals.join("\t") + "\n"
    end
    puts "all scores complete"

    # return filepath
    filepath = @new_expression_file.path
    @new_expression_file.close
    filepath
  end

  # check if all files for this study are still present in the bucket
  # does not check generation tags for consistency - this is just a presence check
  def verify_all_remotes
    missing = []
    files = self.study_files.where(queued_for_deletion: false, human_data: false, :parse_status.ne => 'parsing', status: 'uploaded')
    directories = self.directory_listings.are_synced
    all_locations = files.map(&:bucket_location)
    all_locations += directories.map {|dir| dir.files.map {|file| file['name']}}.flatten
    remotes = Study.firecloud_client.execute_gcloud_method(:get_workspace_files, 0, self.bucket_id)
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
    remotes.any? ? remotes.detect {|remote| remote.name == file_location} : Study.firecloud_client.execute_gcloud_method(:get_workspace_file, 0, self.bucket_id, file_location)
  end

  ###
  #
  # PARSERS
  #
  ###

  # helper method to sanitize arrays of data for use as keys or names (removes quotes, can transform . into _)
  def sanitize_input_array(array, replace_periods=false)
    output = []
    array.each do |entry|
      value = entry.gsub(/(\"|\')/, '')
      output << (replace_periods ? value.gsub(/\./, '_') : value)
    end
    output
  end

  # method to parse master expression scores file for study and populate collection
  # this parser assumes the data is a non-sparse square matrix
  def initialize_gene_expression_data(expression_file, user, opts={local: true})
    begin
      @count = 0
      @child_count = 0
      @message = []
      @last_line = ""
      start_time = Time.zone.now
      @validation_error = false
      @file_location = expression_file.upload.path
      @shift_headers = true
      # error context object for reporting (if enabled)
      error_context = ErrorTracker.format_extra_context(self, expression_file, {opts: opts})
      # remove study description as it's not useful
      error_context['study'].delete('description')

      # before anything starts, check if file has been uploaded locally or needs to be pulled down from FireCloud first
      if !opts[:local] || !expression_file.is_local?
        # make sure data dir exists first
        self.make_data_dir
        Study.firecloud_client.execute_gcloud_method(:download_workspace_file, 0, self.bucket_id, expression_file.bucket_location,
                                                     self.data_store_path, verify: :none)
        @file_location = File.join(self.data_store_path, expression_file.bucket_location)
      end

      # next, check if this is a re-parse job, in which case we need to remove all existing entries first
      if opts[:reparse]
        Gene.where(study_id: self.id, study_file_id: expression_file.id).delete_all
        DataArray.where(study_id: self.id, study_file_id: expression_file.id).delete_all
        expression_file.invalidate_cache_by_file_type
      end

      # determine content type from file contents, not from upload_content_type
      content_type = expression_file.determine_content_type
      # validate headers
      if content_type == 'application/gzip'
        Rails.logger.info "#{Time.zone.now}: Parsing #{expression_file.name}:#{expression_file.id} as application/gzip"
        file = Zlib::GzipReader.open(@file_location)
      else
        Rails.logger.info "#{Time.zone.now}: Parsing #{expression_file.name}:#{expression_file.id} as text/plain"
        file = File.open(@file_location, 'rb')
      end
      # first determine if this is a MM coordinate file or not
      raw_cells = file.readline.rstrip.split(/[\t,]/).map(&:strip)
      cells = self.sanitize_input_array(raw_cells)
      @last_line = "#{expression_file.name}, line 1"
      if !['gene', ''].include?(cells.first.downcase) || cells.size <= 1
        # file did not have correct header information, but may be an export from R which will have one less column
        next_line_size = file.readline.split(/[\t,]/).size
        if cells.size == next_line_size - 1
          # don't shift the headers later as they are beginning with the names of cells (doesn't start with GENE or blank)
          @shift_headers = false
        else
          expression_file.update(parse_status: 'failed')
          @validation_error = true
          @validation_error_message = 'file header validation failed: first header should be GENE or blank followed by cell names'
        end
      end

      file.close
    rescue => e
      ErrorTracker.report_exception(e, user, error_context)
      error_message = "Unexpected error: #{e.message}"
      filename = expression_file.name
      expression_file.remove_local_copy
      expression_file.destroy
      Rails.logger.info Time.zone.now.to_s + ': ' + error_message
      SingleCellMailer.notify_user_parse_fail(user.email, "Error: Expression file: '#{filename}' parse has failed", error_message, self).deliver_now
      raise StandardError, error_message
    end

    # raise validation error if needed
    if @validation_error
      filename = expression_file.name
      expression_file.remove_local_copy
      expression_file.destroy
      Rails.logger.info Time.zone.now.to_s + ': ' + @validation_error_message
      SingleCellMailer.notify_user_parse_fail(user.email, "Error: Expression file: '#{filename}' parse has failed", @validation_error_message, self).deliver_now
      raise StandardError, error_message
    end

    # begin parse
    begin
      Rails.logger.info "#{Time.zone.now}: Beginning expression matrix parse from #{expression_file.name}:#{expression_file.id} for #{self.name}"
      expression_file.update(parse_status: 'parsing')
      # open data file and grab header row with name of all cells, deleting 'GENE' at start
      # determine proper reader
      if content_type == 'application/gzip'
        expression_data = Zlib::GzipReader.open(@file_location)
      else
        expression_data = File.open(@file_location, 'rb')
      end
      raw_cells = expression_data.readline.rstrip.split(/[\t,]/).map(&:strip)
      cells = self.sanitize_input_array(raw_cells)
      @last_line = "#{expression_file.name}, line 1"

      # shift headers if first cell is blank or GENE
      if @shift_headers
        cells.shift
      end

      # validate that new expression matrix does not have repeated cells, raise error if repeats found
      existing_cells = self.all_expression_matrix_cells
      uniques = cells - existing_cells

      unless uniques.size == cells.size
        repeats = cells - uniques
        raise StandardError, "You have re-used the following cell names that were found in another expression matrix in your study (cell names must be unique across all expression matrices): #{repeats.join(', ')}"
      end

      # store study id for later to save memory
      study_id = self._id
      @records = []
      @child_records = []
      # keep a running record of genes already parsed to catch validation errors before they happen
      # this is needed since we're creating records in batch and won't know which gene was responsible
      @genes_parsed = []
      Rails.logger.info "#{Time.zone.now}: Expression data loaded, starting record creation for #{self.name}"
      while !expression_data.eof?
        # grab single row of scores, parse out gene name at beginning
        line = expression_data.readline.strip.encode('UTF-8', invalid: :replace, undef: :replace, replace: '')
        if line.strip.blank?
          next
        else
          raw_row = line.split(/[\t,]/).map(&:strip)
          row = self.sanitize_input_array(raw_row)
          @last_line = "#{expression_file.name}, line #{expression_data.lineno}"

          gene_name = row.shift
          # check for duplicate genes
          if @genes_parsed.include?(gene_name)
            user_error_message = "You have a duplicate gene entry (#{gene_name}) in your gene list.  Please check your file and try again."
            error_message = "Duplicate gene #{gene_name} in #{expression_file.name} (#{expression_file._id}) for study: #{self.name}"
            Rails.logger.info error_message
            raise StandardError, user_error_message
          else
            @genes_parsed << gene_name
          end

          new_gene = Gene.new(name: gene_name, searchable_name: gene_name.downcase, study_file_id: expression_file._id,
                              study_id: self.id)
          @records << new_gene.attributes

          # convert all remaining strings to floats, then store only significant values (!= 0)
          scores = row.map(&:to_f)
          significant_scores = {}
          scores.each_with_index do |score, index|
            unless score == 0.0
              significant_scores[cells[index]] = score
            end
          end
          significant_cells = significant_scores.keys
          significant_exp_values = significant_scores.values

          # chunk cells & values into pieces as necessary
          significant_cells.each_slice(DataArray::MAX_ENTRIES).with_index do |slice, index|
            # create array of all cells for study, send the object attributes rather than the object for bulk insertion
            cell_array = DataArray.new(name: new_gene.cell_key, cluster_name: expression_file.name, array_type: 'cells',
                                       array_index: index + 1, study_file_id: expression_file._id, values: slice,
                                       linear_data_type: 'Gene', linear_data_id: new_gene.id, study_id: self.id)
            @child_records << cell_array.attributes
          end

          significant_exp_values.each_slice(DataArray::MAX_ENTRIES).with_index do |slice, index|
            # create array of all cells for study, sending the object attributes rather than the object for bulk insertion
            score_array = DataArray.new(name: new_gene.score_key, cluster_name: expression_file.name, array_type: 'expression',
                                        array_index: index + 1, study_file_id: expression_file._id, values: slice,
                                        linear_data_type: 'Gene', linear_data_id: new_gene.id, study_id: self.id)
            @child_records << score_array.attributes
          end

          # batch insert records in groups of 1000
          if @child_records.size >= 1000
            Gene.create(@records) # genes must be saved first, otherwise the linear data polymorphic association is invalid and will cause a parse fail
            @count += @records.size
            Rails.logger.info "#{Time.zone.now}: Processed #{@count} genes from #{expression_file.name}:#{expression_file.id} for #{self.name}"
            @records = []
            DataArray.create!(@child_records)
            @child_count += @child_records.size
            Rails.logger.info "#{Time.zone.now}: Processed #{@child_count} child data arrays from #{expression_file.name}:#{expression_file.id} for #{self.name}"
            @child_records = []
          end
        end
      end
      # process last few records
      Gene.create(@records)
      @count += @records.size
      Rails.logger.info "#{Time.zone.now}: Processed #{@count} genes from #{expression_file.name}:#{expression_file.id} for #{self.name}"
      @records = nil

      DataArray.create(@child_records)
      @child_count += @child_records.size
      Rails.logger.info "#{Time.zone.now}: Processed #{@child_count} child data arrays from #{expression_file.name}:#{expression_file.id} for #{self.name}"
      @child_records = nil

      # add processed cells to known cells
      cells.each_slice(DataArray::MAX_ENTRIES).with_index do |slice, index|
        Rails.logger.info "#{Time.zone.now}: Create known cells array ##{index + 1} for #{expression_file.name}:#{expression_file.id} in #{self.name}"
        # use DataArray model & indices directly for better performance; calling study.data_arrays can lead to collection walk
        known_cells = DataArray.new(study_id: self.id, name: "#{expression_file.name} Cells", cluster_name: expression_file.name,
                                    array_type: 'cells', array_index: index + 1, values: slice, study_file_id: expression_file.id,
                                    linear_data_type: 'Study', linear_data_id: self.id)
        known_cells.save
      end

      # run in background to reduce load on job since setting gene count can be expensive both in RAM and execution time
      self.delay.set_gene_count

      # set the default expression label if the user supplied one
      if !self.has_expression_label? && !expression_file.y_axis_label.blank?
        Rails.logger.info "#{Time.zone.now}: Setting default expression label in #{self.name} to '#{expression_file.y_axis_label}'"
        opts = self.default_options
        self.update(default_options: opts.merge(expression_label: expression_file.y_axis_label))
      end

      # clean up, print stats
      expression_data.close
      expression_file.update(parse_status: 'parsed')

      end_time = Time.zone.now
      time = (end_time - start_time).divmod 60.0
      @message << "#{Time.zone.now}: #{expression_file.name} parse completed!"
      @message << "Gene-level entries created: #{@count}"
      @message << "Total Time: #{time.first} minutes, #{time.last} seconds"
      Rails.logger.info @message.join("\n")
      # set initialized to true if possible
      if self.cluster_groups.any? && self.cell_metadata.any? && !self.initialized?
        Rails.logger.info "#{Time.zone.now}: initializing #{self.name}"
        self.update(initialized: true)
        Rails.logger.info "#{Time.zone.now}: #{self.name} successfully initialized"
      end

      begin
        SingleCellMailer.notify_user_parse_complete(user.email, "Expression file: '#{expression_file.name}' has completed parsing", @message, self).deliver_now
      rescue => e
        ErrorTracker.report_exception(e, user, error_context)
        Rails.logger.error "#{Time.zone.now}: Unable to deliver email: #{e.message}"
      end

      Rails.logger.info "#{Time.zone.now}: determining upload status of expression file: #{expression_file.upload_file_name}:#{expression_file.id}"
      # now that parsing is complete, we can move file into storage bucket and delete local (unless we downloaded from FireCloud to begin with)
      # rather than relying on opts[:local], actually check if the file is already in the GCS bucket
      destination = expression_file.bucket_location
      begin
        remote = Study.firecloud_client.execute_gcloud_method(:get_workspace_file, 0, self.bucket_id, destination)
      rescue => e
        ErrorTracker.report_exception(e, user, error_context)
        Rails.logger.error "Error retrieving remote: #{e.message}"
      end
      if remote.nil?
        begin
          Rails.logger.info "#{Time.zone.now}: preparing to upload expression file: #{expression_file.upload_file_name}:#{expression_file.id} to FireCloud"
          self.send_to_firecloud(expression_file)
        rescue => e
          ErrorTracker.report_exception(e, user, error_context)
          Rails.logger.info "#{Time.zone.now}: Expression file: #{expression_file.upload_file_name}:#{expression_file.id} failed to upload to FireCloud due to #{e.message}"
          SingleCellMailer.notify_admin_upload_fail(expression_file, e.message).deliver_now
        end
      else
        # we have the file in FireCloud already, so just delete it
        begin
          Rails.logger.info "#{Time.zone.now}: found remote version of #{expression_file.upload_file_name}: #{remote.name} (#{remote.generation})"
          run_at = 15.seconds.from_now
          Delayed::Job.enqueue(UploadCleanupJob.new(self, expression_file, 0), run_at: run_at)
          Rails.logger.info "#{Time.zone.now}: cleanup job for #{expression_file.upload_file_name}:#{expression_file.id} scheduled for #{run_at}"
        rescue => e
          ErrorTracker.report_exception(e, user, error_context)
          # we don't really care if the delete fails, we can always manually remove it later as the file is in FireCloud already
          Rails.logger.error "#{Time.zone.now}: Could not delete #{expression_file.name}:#{expression_file.id} in study #{self.name}; aborting"
          SingleCellMailer.admin_notification('Local file deletion failed', nil, "The file at #{@file_location} failed to clean up after parsing, please remove.").deliver_now
        end
      end
    rescue => e
      ErrorTracker.report_exception(e, user, error_context)
      # error has occurred, so clean up records and remove file
      Gene.where(study_id: self.id, study_file_id: expression_file.id).delete_all
      DataArray.where(study_id: self.id, study_file_id: expression_file.id).delete_all
      filename = expression_file.name
      expression_file.remove_local_copy
      expression_file.destroy
      error_message = "#{@last_line}: #{e.message}"
      Rails.logger.info Time.zone.now.to_s + ': ' + error_message
      SingleCellMailer.notify_user_parse_fail(user.email, "Error: Gene Expression matrix: '#{filename}' parse has failed", error_message, self).deliver_now
    end
    true
  end

  # parse single cluster coordinate & metadata file (name, x, y, z, metadata_cols* format)
  # uses cluster_group model instead of single clusters; group membership now defined by metadata
  # stores point data in cluster_group_data_arrays instead of single_cells and cluster_points
  def initialize_cluster_group_and_data_arrays(ordinations_file, user, opts={local: true})
    begin
      error_context = ErrorTracker.format_extra_context(self, ordinations_file, {opts: opts})
      # remove study description as it's not useful
      error_context['study'].delete('description')
      @file_location = ordinations_file.upload.path
      # before anything starts, check if file has been uploaded locally or needs to be pulled down from FireCloud first
      if !opts[:local] || !ordinations_file.is_local?
        # make sure data dir exists first
        Rails.logger.info "Localizing file: #{ordinations_file.upload_file_name} in #{self.data_store_path}"
        self.make_data_dir
        Study.firecloud_client.execute_gcloud_method(:download_workspace_file, 0, self.bucket_id, ordinations_file.bucket_location,
                                                     self.data_store_path, verify: :none)
        @file_location = File.join(self.data_store_path, ordinations_file.bucket_location)
      end

      # next, check if this is a re-parse job, in which case we need to remove all existing entries first
      if opts[:reparse]
        ClusterGroup.where(study_id: self.id, study_file_id: ordinations_file.id).delete_all
        DataArray.where(study_id: self.id, study_file_id: ordinations_file.id).delete_all
        ordinations_file.invalidate_cache_by_file_type
      end

      # determine content type from file contents, not from upload_content_type
      content_type = ordinations_file.determine_content_type
      # validate headers
      if content_type == 'application/gzip'
        Rails.logger.info "#{Time.zone.now}: Parsing #{ordinations_file.name}:#{ordinations_file.id} as application/gzip"
        d_file = Zlib::GzipReader.open(@file_location)
      else
        Rails.logger.info "#{Time.zone.now}: Parsing #{ordinations_file.name}:#{ordinations_file.id} as text/plain"
        d_file = File.open(@file_location, 'rb')
      end

      # validate headers of cluster file
      @validation_error = false
      start_time = Time.zone.now
      headers = d_file.readline.split(/[\t,]/).map(&:strip)
      second_header = d_file.readline.split(/[\t,]/).map(&:strip)
      @last_line = "#{ordinations_file.name}, line 1"
      # must have at least NAME, X and Y fields
      unless (headers & %w(NAME X Y)).size == 3 && second_header.include?('TYPE')
        ordinations_file.update(parse_status: 'failed')
        @validation_error = true
      end
      d_file.close
    rescue => e
      ErrorTracker.report_exception(e, user, error_context)
      ordinations_file.update(parse_status: 'failed')
      error_message = "#{e.message}"
      Rails.logger.info Time.zone.now.to_s + ': ' + error_message
      filename = ordinations_file.upload_file_name
      ordinations_file.remove_local_copy
      ordinations_file.destroy
      SingleCellMailer.notify_user_parse_fail(user.email, "Error: Cluster file: '#{filename}' parse has failed", error_message, self).deliver_now
      raise StandardError, error_message
    end

    # raise validation error if needed
    if @validation_error
      error_message = "file header validation failed: should be at least NAME, X, Y with second line starting with TYPE"
      Rails.logger.info Time.zone.now.to_s + ': ' + error_message
      filename = ordinations_file.upload_file_name
      ordinations_file.remove_local_copy
      ordinations_file.destroy
      SingleCellMailer.notify_user_parse_fail(user.email, "Error: Cluster file: '#{filename}' parse has failed", error_message, self).deliver_now
      raise StandardError, error_message
    end

    @message = []
    @cluster_metadata = []
    @point_count = 0
    # begin parse
    begin
      cluster_name = ordinations_file.name
      Rails.logger.info "#{Time.zone.now}: Beginning cluster initialization using #{ordinations_file.upload_file_name}:#{ordinations_file.id} for cluster: #{cluster_name} in #{self.name}"
      ordinations_file.update(parse_status: 'parsing')

      if content_type == 'application/gzip'
        cluster_data = Zlib::GzipReader.open(@file_location)
      else
        cluster_data = File.open(@file_location, 'rb')
      end

      raw_header_data = cluster_data.readline.encode('UTF-8', invalid: :replace, undef: :replace, replace: '').split(/[\t,]/).map(&:strip)
      raw_type_data = cluster_data.readline.encode('UTF-8', invalid: :replace, undef: :replace, replace: '').split(/[\t,]/).map(&:strip)
      header_data = self.sanitize_input_array(raw_header_data)
      type_data = self.sanitize_input_array(raw_type_data).map(&:downcase)

      # determine if 3d coordinates have been provided
      is_3d = header_data.include?('Z')
      cluster_type = is_3d ? '3d' : '2d'

      # grad header indices, z index will be nil if no 3d data
      name_index = header_data.index('NAME')
      x_index = header_data.index('X')
      y_index = header_data.index('Y')
      z_index = header_data.index('Z')

      # determine what extra metadata has been provided
      metadata_headers = header_data - %w(NAME X Y Z)
      metadata_headers.each do |metadata|
        idx = header_data.index(metadata)
        # store temporary object with metadata name, index location and data type (group or numeric)
        point_metadata = {
            name: metadata,
            index: idx,
            type: type_data[idx].downcase # downcase type to avoid case matching issues later
        }
        @cluster_metadata << point_metadata
      end

      # create cluster object for use later
      Rails.logger.info "#{Time.zone.now}: Creating cluster group object: #{cluster_name} in study: #{self.name}"
      @domain_ranges = {
          x: [ordinations_file.x_axis_min, ordinations_file.x_axis_max],
          y: [ordinations_file.y_axis_min, ordinations_file.y_axis_max]
      }
      required_values = 4
      if is_3d
        @domain_ranges[:z] = [ordinations_file.z_axis_min, ordinations_file.z_axis_max]
        required_values = 6
      end

      # check if ranges are valid
      unless @domain_ranges.values.flatten.compact.size == required_values
        @domain_ranges = nil
      end

      @cluster_group = self.cluster_groups.build(name: cluster_name,
                                                 study_file_id: ordinations_file._id,
                                                 cluster_type: cluster_type,
                                                 domain_ranges: @domain_ranges
      )

      # add cell-level annotation definitions and save (will be used to populate dropdown menu)
      # this object will not be saved until after parse is done as we need to collect all possible values
      # for group annotations (not needed for numeric)
      cell_annotations = []
      @cluster_metadata.each do |metadata|
        cell_annotations << {
            name: metadata[:name],
            type: metadata[:type],
            header_index: metadata[:index],
            values: []
        }
      end
      @cluster_group.save

      # container to store temporary data arrays until ready to save
      @data_arrays = []
      # create required data_arrays (name, x, y)
      @data_arrays[name_index] = @cluster_group.data_arrays.build(name: 'text', cluster_name: cluster_name, array_type: 'cells',
                                                                  array_index: 1, study_file_id: ordinations_file._id,
                                                                  study_id: self.id, values: [])
      @data_arrays[x_index] = @cluster_group.data_arrays.build(name: 'x', cluster_name: cluster_name, array_type: 'coordinates',
                                                               array_index: 1, study_file_id: ordinations_file._id,
                                                               study_id: self.id, values: [])
      @data_arrays[y_index] = @cluster_group.data_arrays.build(name: 'y', cluster_name: cluster_name, array_type: 'coordinates',
                                                               array_index: 1, study_file_id: ordinations_file._id,
                                                               study_id: self.id, values: [])

      # add optional data arrays (z, metadata)
      if is_3d
        @data_arrays[z_index] = @cluster_group.data_arrays.build(name: 'z', cluster_name: cluster_name, array_type: 'coordinates',
                                                               array_index: 1, study_file_id: ordinations_file._id,
                                                               study_id: self.id, values: [])
      end
      @cluster_metadata.each do |metadata|
        @data_arrays[metadata[:index]] = @cluster_group.data_arrays.build(name: metadata[:name], cluster_name: cluster_name,
                                                                          array_type: 'annotations', array_index: 1,
                                                                          study_file_id: ordinations_file._id,
                                                                          study_id: self.id, values: [])
      end

      Rails.logger.info "#{Time.zone.now}: Headers/Metadata loaded for cluster initialization using #{ordinations_file.upload_file_name} for cluster: #{cluster_name} in #{self.name}"
      # begin reading data
      while !cluster_data.eof?
        line = cluster_data.readline.strip.encode('UTF-8', invalid: :replace, undef: :replace, replace: '')
        if line.strip.blank?
          next
        else
          @point_count += 1
          @last_line = "#{ordinations_file.name}, line #{cluster_data.lineno}"
          raw_vals = line.split(/[\t,]/).map(&:strip)
          vals = self.sanitize_input_array(raw_vals)
          # assign value to corresponding data_array by column index
          vals.each_with_index do |val, index|
            if @data_arrays[index].values.size >= DataArray::MAX_ENTRIES
              # array already has max number of values, so save it and replace it with a new data array
              # of same name & type with array_index incremented by 1
              current_data_array_index = @data_arrays[index].array_index
              data_array = @data_arrays[index]
              Rails.logger.info "#{Time.zone.now}: Saving data array: #{data_array.name}-#{data_array.array_type}-#{data_array.array_index} using #{ordinations_file.upload_file_name}:#{ordinations_file.id} for cluster: #{cluster_name} in #{self.name}"
              data_array.save
              new_data_array = @cluster_group.data_arrays.build(name: data_array.name, cluster_name: data_array.cluster_name,
                                                                array_type: data_array.array_type, array_index: current_data_array_index + 1,
                                                                study_file_id: ordinations_file._id, study_id: self.id, values: [])
              @data_arrays[index] = new_data_array
            end
            # determine whether or not value needs to be cast as a float or not
            if type_data[index] == 'numeric'
              @data_arrays[index].values << val.to_f
            else
              @data_arrays[index].values << val
              # check if this is a group annotation, and if so store its value in the cluster_group.cell_annotations
              # hash if the value is not already present
              if type_data[index] == 'group'
                existing_vals = cell_annotations.find {|annot| annot[:name] == header_data[index]}
                metadata_idx = cell_annotations.index(existing_vals)
                unless existing_vals[:values].include?(val)
                  cell_annotations[metadata_idx][:values] << val
                  Rails.logger.info "#{Time.zone.now}: Adding #{val} to #{@cluster_group.name} list of group values for #{header_data[index]}"
                end
              end
            end
          end
        end

      end
      # clean up
      @data_arrays.each do |data_array|
        Rails.logger.info "#{Time.zone.now}: Saving data array: #{data_array.name}-#{data_array.array_type}-#{data_array.array_index} using #{ordinations_file.upload_file_name}:#{ordinations_file.id} for cluster: #{cluster_name} in #{self.name}"
        data_array.save
      end
      cluster_data.close

      # save cell_annotations to cluster_group object
      @cluster_group.update_attributes(cell_annotations: cell_annotations)
      # reload cluster_group to use in messaging
      @cluster_group = ClusterGroup.find_by(study_id: self.id, study_file_id: ordinations_file.id, name: ordinations_file.name)
      ordinations_file.update(parse_status: 'parsed')
      end_time = Time.zone.now
      time = (end_time - start_time).divmod 60.0
      # assemble email message parts
      @message << "#{ordinations_file.upload_file_name} parse completed!"
      @message << "Cluster created: #{@cluster_group.name}, type: #{@cluster_group.cluster_type}"
      if @cluster_group.cell_annotations.any?
        @message << "Annotations:"
        @cluster_group.cell_annotations.each do |annot|
          @message << "#{annot['name']}: #{annot['type']}#{annot['type'] == 'group' ? ' (' + annot['values'].join(',') + ')' : nil}"
        end
      end
      @message << "Total points in cluster: #{@point_count}"
      @message << "Total Time: #{time.first} minutes, #{time.last} seconds"
      # set initialized to true if possible
      if self.genes.any? && self.cell_metadata.any? && !self.initialized?
        Rails.logger.info "#{Time.zone.now}: initializing #{self.name}"
        self.update(initialized: true)
        Rails.logger.info "#{Time.zone.now}: #{self.name} successfully initialized"
      end

      # check to see if a default cluster & annotation have been set yet
      # must load reference to self into a local variable as we cannot call self.save to update attributes
      study_obj = Study.find(self.id)
      if study_obj.default_options[:cluster].nil?
        study_obj.default_options[:cluster] = @cluster_group.name
      end

      if study_obj.default_options[:annotation].nil?
        if @cluster_group.cell_annotations.any?
          cell_annot = @cluster_group.cell_annotations.first
          study_obj.default_options[:annotation] = "#{cell_annot[:name]}--#{cell_annot[:type]}--cluster"
          if cell_annot[:type] == 'numeric'
            # set a default color profile if this is a numeric annotation
            study_obj.default_options[:color_profile] = 'Reds'
          end
        elsif study_obj.cell_metadata.any?
          metadatum = study_obj.cell_metadata.first
          study_obj.default_options[:annotation] = "#{metadatum.name}--#{metadatum.annotation_type}--study"
          if metadatum.annotation_type == 'numeric'
            # set a default color profile if this is a numeric annotation
            study_obj.default_options[:color_profile] = 'Reds'
          end
        else
          # no possible annotations to set, but enter annotation key into default_options
          study_obj.default_options[:annotation] = nil
        end
      end

      # update study.default_options
      study_obj.save

      # create subsampled data_arrays for visualization
      cell_metadata = CellMetadatum.where(study_id: self.id)
      # determine how many levels to subsample based on size of cluster_group
      required_subsamples = ClusterGroup::SUBSAMPLE_THRESHOLDS.select {|sample| sample < @cluster_group.points}
      required_subsamples.each do |sample_size|
        # create cluster-based annotation subsamples first
        if @cluster_group.cell_annotations.any?
          @cluster_group.cell_annotations.each do |cell_annot|
            @cluster_group.delay.generate_subsample_arrays(sample_size, cell_annot[:name], cell_annot[:type], 'cluster')
          end
        end
        # create study-based annotation subsamples
        cell_metadata.each do |metadata|
          @cluster_group.delay.generate_subsample_arrays(sample_size, metadata.name, metadata.annotation_type, 'study')
        end
      end

      begin
        SingleCellMailer.notify_user_parse_complete(user.email, "Cluster file: '#{ordinations_file.upload_file_name}' has completed parsing", @message, self).deliver_now
      rescue => e
        ErrorTracker.report_exception(e, user, error_context)
        Rails.logger.error "#{Time.zone.now}: Unable to deliver email: #{e.message}"
      end

      Rails.logger.info "#{Time.zone.now}: determining upload status of ordinations file: #{ordinations_file.upload_file_name}:#{ordinations_file.id}"

      # now that parsing is complete, we can move file into storage bucket and delete local (unless we downloaded from FireCloud to begin with)
      destination = ordinations_file.bucket_location
      begin
        remote = Study.firecloud_client.execute_gcloud_method(:get_workspace_file, 0, self.bucket_id, destination)
      rescue => e
        ErrorTracker.report_exception(e, user, error_context)
        Rails.logger.error "Error retrieving remote: #{e.message}"
      end
      if remote.nil?
        begin
          Rails.logger.info "#{Time.zone.now}: preparing to upload ordinations file: #{ordinations_file.upload_file_name}:#{ordinations_file.id} to FireCloud"
          self.send_to_firecloud(ordinations_file)
        rescue => e
          ErrorTracker.report_exception(e, user, error_context)
          Rails.logger.info "#{Time.zone.now}: Cluster file: #{ordinations_file.upload_file_name}:#{ordinations_file.id} failed to upload to FireCloud due to #{e.message}"
          SingleCellMailer.notify_admin_upload_fail(ordinations_file, e.message).deliver_now
        end
      else
        # we have the file in FireCloud already, so just delete it
        begin
          Rails.logger.info "#{Time.zone.now}: found remote version of #{ordinations_file.upload_file_name}: #{remote.name} (#{remote.generation})"
          run_at = 15.seconds.from_now
          Delayed::Job.enqueue(UploadCleanupJob.new(self, ordinations_file, 0), run_at: run_at)
          Rails.logger.info "#{Time.zone.now}: cleanup job for #{ordinations_file.upload_file_name}:#{ordinations_file.id} scheduled for #{run_at}"
        rescue => e
          ErrorTracker.report_exception(e, user, error_context)
          # we don't really care if the delete fails, we can always manually remove it later as the file is in FireCloud already
          Rails.logger.error "#{Time.zone.now}: Could not delete #{ordinations_file.name}:#{ordinations_file.id} in study #{self.name}; aborting"
          SingleCellMailer.admin_notification('Local file deletion failed', nil, "The file at #{@file_location} failed to clean up after parsing, please remove.").deliver_now
        end
      end
    rescue => e
      ErrorTracker.report_exception(e, user, error_context)
      # error has occurred, so clean up records and remove file
      ClusterGroup.where(study_file_id: ordinations_file.id).delete_all
      DataArray.where(study_file_id: ordinations_file.id).delete_all
      filename = ordinations_file.upload_file_name
      ordinations_file.remove_local_copy
      ordinations_file.destroy
      error_message = "#{@last_line} ERROR: #{e.message}"
      Rails.logger.info Time.zone.now.to_s + ': ' + error_message
      SingleCellMailer.notify_user_parse_fail(user.email, "Error: Cluster file: '#{filename}' parse has failed", error_message, self).deliver_now
    end
    true
  end

  # parse a coordinate labels file and create necessary data_array objects
  # coordinate labels are specific to a cluster_group
  def initialize_coordinate_label_data_arrays(coordinate_file, user, opts={local: true})
    begin
      error_context = ErrorTracker.format_extra_context(self, coordinate_file, {opts: opts})
      # remove study description as it's not useful
      error_context['study'].delete('description')
      @file_location = coordinate_file.upload.path
      # before anything starts, check if file has been uploaded locally or needs to be pulled down from FireCloud first
      if !opts[:local] || !coordinate_file.is_local?
        # make sure data dir exists first
        self.make_data_dir
        Study.firecloud_client.execute_gcloud_method(:download_workspace_file, 0, self.bucket_id, coordinate_file.bucket_location,
                                                     self.data_store_path, verify: :none)
        @file_location = File.join(self.data_store_path, coordinate_file.bucket_location)
      end

      # next, check if this is a re-parse job, in which case we need to remove all existing entries first
      if opts[:reparse]
        DataArray.where(study_id: self.id, study_file_id: coordinate_file.id).delete_all
        coordinate_file.invalidate_cache_by_file_type
      end

      # determine content type from file contents, not from upload_content_type
      content_type = coordinate_file.determine_content_type
      # validate headers
      if content_type == 'application/gzip'
        Rails.logger.info "#{Time.zone.now}: Parsing #{coordinate_file.name}:#{coordinate_file.id} as application/gzip"
        c_file = Zlib::GzipReader.open(@file_location)
      else
        Rails.logger.info "#{Time.zone.now}: Parsing #{coordinate_file.name}:#{coordinate_file.id} as text/plain"
        c_file = File.open(@file_location, 'rb')
      end

      # validate headers of coordinate file
      @validation_error = false
      start_time = Time.zone.now
      headers = c_file.readline.split(/[\t,]/).map(&:strip)
      @last_line = "#{coordinate_file.name}, line 1"
      # must have at least NAME, X and Y fields
      unless (headers & %w(X Y LABELS)).size == 3
        coordinate_file.update(parse_status: 'failed')
        @validation_error = true
      end
      c_file.close
    rescue => e
      ErrorTracker.report_exception(e, user, error_context)
      coordinate_file.update(parse_status: 'failed')
      error_message = "#{e.message}"
      Rails.logger.info Time.zone.now.to_s + ': ' + error_message
      filename = coordinate_file.upload_file_name
      coordinate_file.remove_local_copy
      coordinate_file.destroy
      SingleCellMailer.notify_user_parse_fail(user.email, "Error: Coordinate Labels file: '#{filename}' parse has failed", error_message, self).deliver_now
      raise StandardError, error_message
    end

    # raise validation error if needed
    if @validation_error
      error_message = "file header validation failed: should be at least NAME, X, Y, LABELS"
      Rails.logger.info Time.zone.now.to_s + ': ' + error_message
      filename = coordinate_file.upload_file_name
      if File.exist?(@file_location)
        File.delete(@file_location)
        if Dir.exist?(File.join(self.data_store_path, coordinate_file.id))
          Dir.chdir(self.data_store_path)
          Dir.rmdir(coordinate_file.id)
        end
      end
      coordinate_file.destroy
      SingleCellMailer.notify_user_parse_fail(user.email, "Error: Coordinate Labels file: '#{filename}' parse has failed", error_message, self).deliver_now
      raise StandardError, error_message
    end

    # set up containers
    @labels_created = []
    @message = []
    begin
      # load target cluster
      cluster = coordinate_file.bundle_parent

      Rails.logger.info "#{Time.zone.now}: Beginning coordinate label initialization using #{coordinate_file.upload_file_name}:#{coordinate_file.id} for cluster: #{cluster.name} in #{self.name}"
      coordinate_file.update(parse_status: 'parsing')

      if content_type == 'application/gzip'
        coordinate_data = Zlib::GzipReader.open(@file_location)
      else
        coordinate_data = File.open(@file_location, 'rb')
      end

      raw_header_data = coordinate_data.readline.encode('UTF-8', invalid: :replace, undef: :replace, replace: '').split(/[\t,]/).map(&:strip)
      header_data = self.sanitize_input_array(raw_header_data)

      # determine if 3d coordinates have been provided
      is_3d = header_data.include?('Z')

      # grad header indices, z index will be nil if no 3d data
      x_index = header_data.index('X')
      y_index = header_data.index('Y')
      z_index = header_data.index('Z')
      label_index = header_data.index('LABELS')

      # container to store temporary data arrays until ready to save
      @data_arrays = []
      # create required data_arrays (name, x, y)
      @data_arrays[x_index] = cluster.data_arrays.build(name: 'x', cluster_name: cluster.name, array_type: 'labels',
                                                        array_index: 1, study_file_id: coordinate_file._id,
                                                        study_id: self.id, values: [])
      @data_arrays[y_index] = cluster.data_arrays.build(name: 'y', cluster_name: cluster.name, array_type: 'labels',
                                                        array_index: 1, study_file_id: coordinate_file._id,
                                                        study_id: self.id, values: [])
      @data_arrays[label_index] = cluster.data_arrays.build(name: 'text', cluster_name: cluster.name, array_type: 'labels',
                                                            array_index: 1, study_file_id: coordinate_file._id,
                                                            study_id: self.id, values: [])

      # add optional data arrays (z, metadata)
      if is_3d
        @data_arrays[z_index] = cluster.data_arrays.build(name: 'z', cluster_name: cluster.name, array_type: 'labels',
                                                       array_index: 1, study_file_id: coordinate_file._id, study_id: self.id,
                                                       values: [])
      end

      Rails.logger.info "#{Time.zone.now}: Headers/Metadata loaded for coordinate file initialization using #{coordinate_file.upload_file_name}:#{coordinate_file.id} for cluster: #{cluster.name} in #{self.name}"
      # begin reading data
      while !coordinate_data.eof?
        line = coordinate_data.readline.strip.encode('UTF-8', invalid: :replace, undef: :replace, replace: '')
        if line.strip.blank?
          next
        else
          @last_line = "#{coordinate_file.name}, line #{coordinate_data.lineno}"
          raw_vals = line.split(/[\t,]/).map(&:strip)
          vals = self.sanitize_input_array(raw_vals)
          # assign value to corresponding data_array by column index
          vals.each_with_index do |val, index|
            if @data_arrays[index].values.size >= DataArray::MAX_ENTRIES
              # array already has max number of values, so save it and replace it with a new data array
              # of same name & type with array_index incremented by 1
              current_data_array_index = @data_arrays[index].array_index
              data_array = @data_arrays[index]
              Rails.logger.info "#{Time.zone.now}: Saving full-length data array: #{data_array.name}-#{data_array.array_type}-#{data_array.array_index} using #{coordinate_file.upload_file_name}:#{coordinate_file.id} for cluster: #{cluster.name} in #{self.name}; initializing new array index #{current_data_array_index + 1}"
              data_array.save
              if data_array.array_type == 'labels'
                @labels_created << data_array
              end
              new_data_array = cluster.data_arrays.build(name: data_array.name, cluster_name: data_array.cluster_name,
                                                         array_type: data_array.array_type, array_index: current_data_array_index + 1,
                                                         study_file_id: coordinate_file._id, study_id: self.id, values: [])
              @data_arrays[index] = new_data_array
            end
            # determine whether or not value needs to be cast as a float or not (only values at label index stay as a string)
            if index == label_index
              @data_arrays[index].values << val
            else
              @data_arrays[index].values << val.to_f
            end
          end
        end

      end

      # clean up
      @data_arrays.each do |data_array|
        Rails.logger.info "#{Time.zone.now}: Saving data array: #{data_array.name}-#{data_array.array_type}-#{data_array.array_index} using #{coordinate_file.upload_file_name}:#{coordinate_file.id} for cluster: #{cluster.name} in #{self.name}"
        data_array.save
      end
      coordinate_data.close
      coordinate_file.update(parse_status: 'parsed')
      end_time = Time.zone.now
      time = (end_time - start_time).divmod 60.0
      # assemble email message parts
      @message << "#{coordinate_file.upload_file_name} parse completed!"
      @message << "Labels created (#{@labels_created.size}: #{@labels_created.join(', ')}"
      @message << "Total Time: #{time.first} minutes, #{time.last} seconds"

      # expire cluster caches to load label data on render
      cluster_study_file = cluster.study_file
      cluster_study_file.invalidate_cache_by_file_type

      begin
        SingleCellMailer.notify_user_parse_complete(user.email, "Coordinate Label file: '#{coordinate_file.upload_file_name}' has completed parsing", @message, self).deliver_now
      rescue => e
        ErrorTracker.report_exception(e, user, error_context)
        Rails.logger.error "#{Time.zone.now}: Unable to deliver email: #{e.message}"
      end

      Rails.logger.info "#{Time.zone.now}: determining upload status of coordinate labels file: #{coordinate_file.upload_file_name}:#{coordinate_file.id}"

      # now that parsing is complete, we can move file into storage bucket and delete local (unless we downloaded from FireCloud to begin with)
      destination = coordinate_file.bucket_location
      begin
        remote = Study.firecloud_client.execute_gcloud_method(:get_workspace_file, 0, self.bucket_id, destination)
      rescue => e
        ErrorTracker.report_exception(e, user, error_context)
        Rails.logger.error "Error retrieving remote: #{e.message}"
      end
      if remote.nil?
        begin
          Rails.logger.info "#{Time.zone.now}: preparing to upload ordinations file: #{coordinate_file.upload_file_name}:#{coordinate_file.id} to FireCloud"
          self.send_to_firecloud(coordinate_file)
        rescue => e
          ErrorTracker.report_exception(e, user, error_context)
          Rails.logger.info "#{Time.zone.now}: Cluster file: #{coordinate_file.upload_file_name}:#{coordinate_file.id} failed to upload to FireCloud due to #{e.message}"
          SingleCellMailer.notify_admin_upload_fail(coordinate_file, e.message).deliver_now
        end
      else
        # we have the file in FireCloud already, so just delete it
        begin
          Rails.logger.info "#{Time.zone.now}: found remote version of #{coordinate_file.upload_file_name}: #{remote.name} (#{remote.generation})"
          run_at = 15.seconds.from_now
          Delayed::Job.enqueue(UploadCleanupJob.new(self, coordinate_file, 0), run_at: run_at)
          Rails.logger.info "#{Time.zone.now}: cleanup job for #{coordinate_file.upload_file_name}:#{coordinate_file.id} scheduled for #{run_at}"
        rescue => e
          ErrorTracker.report_exception(e, user, error_context)
          # we don't really care if the delete fails, we can always manually remove it later as the file is in FireCloud already
          Rails.logger.error "#{Time.zone.now}: Could not delete #{coordinate_file.name}:#{coordinate_file.id} in study #{self.name}; aborting"
          SingleCellMailer.admin_notification('Local file deletion failed', nil, "The file at #{@file_location} failed to clean up after parsing, please remove.").deliver_now
        end
      end
    rescue => e
      ErrorTracker.report_exception(e, user, error_context)
      # error has occurred, so clean up records and remove file
      DataArray.where(study_file_id: coordinate_file.id).delete_all
      filename = coordinate_file.upload_file_name
      coordinate_file.remove_local_copy
      coordinate_file.destroy
      error_message = "#{@last_line} ERROR: #{e.message}"
      Rails.logger.info Time.zone.now.to_s + ': ' + error_message
      SingleCellMailer.notify_user_parse_fail(user.email, "Error: Coordinate Labels file: '#{filename}' parse has failed", error_message, self).deliver_now

    end
  end

  # parse a study metadata file and create necessary cell_metadatum objects
  def initialize_cell_metadata(metadata_file, user, opts={local: true})
    begin
      error_context = ErrorTracker.format_extra_context(self, metadata_file, {opts: opts})
      # remove study description as it's not useful
      error_context['study'].delete('description')
      @file_location = metadata_file.upload.path
      # before anything starts, check if file has been uploaded locally or needs to be pulled down from FireCloud first
      if !opts[:local] || !metadata_file.is_local?
        # make sure data dir exists first
        self.make_data_dir
        Study.firecloud_client.execute_gcloud_method(:download_workspace_file, 0, self.bucket_id, metadata_file.bucket_location,
                                                     self.data_store_path, verify: :none)
        @file_location = File.join(self.data_store_path, metadata_file.bucket_location)
      end

      # next, check if this is a re-parse job, in which case we need to remove all existing entries first
      if opts[:reparse]
        CellMetadatum.where(study_id: self.id).delete_all
        DataArray.where(study_file_id: metadata_file.id).delete_all
        metadata_file.invalidate_cache_by_file_type
      end

      # determine content type from file contents, not from upload_content_type
      content_type = metadata_file.determine_content_type
      # validate headers
      if content_type == 'application/gzip'
        Rails.logger.info "#{Time.zone.now}: Parsing #{metadata_file.name}:#{metadata_file.id} as application/gzip"
        m_file = Zlib::GzipReader.open(@file_location)
      else
        Rails.logger.info "#{Time.zone.now}: Parsing #{metadata_file.name}:#{metadata_file.id} as text/plain"
        m_file = File.open(@file_location, 'rb')
      end

      # validate headers of metadata file
      @validation_error = false
      start_time = Time.zone.now
      Rails.logger.info "#{Time.zone.now}: Validating metadata file headers for #{metadata_file.name}:#{metadata_file.id} in #{self.name}"
      headers = m_file.readline.split(/[\t,]/).map(&:strip)
      @last_line = "#{metadata_file.name}, line 1"
      second_header = m_file.readline.split(/[\t,]/).map {|entry| entry.downcase.strip}
      @last_line = "#{metadata_file.name}, line 2"
      # must have at least NAME and one column, plus TYPE and one value of group or numeric in second line
      unless headers.include?('NAME') && headers.size > 1 && (second_header.uniq.sort - %w(group numeric type)).size == 0 && second_header.size > 1
        metadata_file.update(parse_status: 'failed')
        @validation_error = true
      end
      m_file.close
    rescue => e
      ErrorTracker.report_exception(e, user, error_context)
      filename = metadata_file.upload_file_name
      metadata_file.remove_local_copy
      metadata_file.destroy
      error_message = "#{@last_line} ERROR: #{e.message}"
      Rails.logger.info Time.zone.now.to_s + ': ' + error_message
      SingleCellMailer.notify_user_parse_fail(user.email, "Error: Metadata file: '#{filename}' parse has failed", error_message, self).deliver_now
      raise StandardError, error_message
    end

    # raise validation error if needed
    if @validation_error
      error_message = "file header validation failed: should be at least NAME and one other column with second line starting with TYPE followed by either 'group' or 'numeric'"
      filename = metadata_file.upload_file_name
      metadata_file.destroy
      Rails.logger.info Time.zone.now.to_s + ': ' + error_message
      SingleCellMailer.notify_user_parse_fail(user.email, "Error: Metadata file: '#{filename}' parse has failed", error_message, self).deliver_now
      raise StandardError, error_message
    end

    @metadata_records = []
    @metadata_data_arrays = []
    @message = []
    # begin parse
    begin
      Rails.logger.info "#{Time.zone.now}: Beginning metadata initialization using #{metadata_file.upload_file_name}:#{metadata_file.id} in #{self.name}"
      metadata_file.update(parse_status: 'parsing')
      # open files for parsing and grab header & type data
      if content_type == 'application/gzip'
        metadata_data = Zlib::GzipReader.open(@file_location)
      else
        metadata_data = File.open(@file_location, 'rb')
      end
      raw_header_data = metadata_data.readline.encode('UTF-8', invalid: :replace, undef: :replace, replace: '').split(/[\t,]/).map(&:strip)
      raw_type_data = metadata_data.readline.encode('UTF-8', invalid: :replace, undef: :replace, replace: '').split(/[\t,]/).map(&:strip)
      header_data = self.sanitize_input_array(raw_header_data)
      type_data = self.sanitize_input_array(raw_type_data).map(&:downcase)
      name_index = header_data.index('NAME')

      # build study_metadata objects for use later
      header_data.each_with_index do |header, index|
        # don't need an object for the cell names, only metadata values
        unless index == name_index
          m_obj = self.cell_metadata.build(name: header, annotation_type: type_data[index], study_file_id: metadata_file._id, values: [])
          @metadata_records[index] = m_obj
          @metadata_data_arrays[index] = m_obj.data_arrays.build(name: m_obj.name, cluster_name: metadata_file.name,
                                                                      array_type: 'annotations', array_index: 1,
                                                                      study_id: self.id, study_file_id: metadata_file.id,
                                                                      values: [])
        end
      end

      # array to hold all cell names
      all_cells = []

      Rails.logger.info "#{Time.zone.now}: Study metadata objects initialized using: #{metadata_file.name}:#{metadata_file.id} for #{self.name}; beginning parse"
      # read file data
      while !metadata_data.eof?
        line = metadata_data.readline.strip.encode('UTF-8', invalid: :replace, undef: :replace, replace: '')
        if line.strip.blank?
          next
        else
          @last_line = "#{metadata_file.name}, line #{metadata_data.lineno}"
          raw_vals = line.split(/[\t,]/).map(&:strip)
          vals = self.sanitize_input_array(raw_vals)

          # assign values to correct cell_metadata object
          vals.each_with_index do |val, index|
            unless index == name_index
              if @metadata_data_arrays[index].values.size >= DataArray::MAX_ENTRIES
                # data array already has max number of values, so save it and replace it with a new data_array of same name & type
                metadata = @metadata_records[index]
                array = @metadata_data_arrays[index]
                Rails.logger.info "#{Time.zone.now}: Saving cell metadata data array: #{array.name}-#{array.array_index} using #{metadata_file.upload_file_name}:#{metadata_file.id} in #{self.name}"
                array.save
                new_array = metadata.data_arrays.build(name: metadata.name, array_type: 'annotations', cluster_name: metadata_file.name,
                                                       array_index: array.array_index + 1, study_file_id: metadata_file._id,
                                                       study_id: self.id, values: [])
                @metadata_data_arrays[index] = new_array
              end
              # determine whether or not value needs to be cast as a float or not
              if type_data[index] == 'numeric'
                @metadata_data_arrays[index].values << val.to_f
              else
                @metadata_data_arrays[index].values << val
                # determine if a new unique value needs to be stored in values array
                if type_data[index] == 'group' && !@metadata_records[index].values.include?(val)
                  @metadata_records[index].values << val
                  Rails.logger.info "#{Time.zone.now}: Adding #{val} to #{@metadata_records[index].name} list of group values for #{header_data[index]}"
                end
              end
            else
              # store the cell name for use later
              all_cells << val
            end
          end
        end
      end

      # create all cells arrays
      all_cells.each_slice(DataArray::MAX_ENTRIES).with_index do |slice, index|
        Rails.logger.info "#{Time.zone.now}: Create all cells array ##{index + 1} for #{metadata_file.name}:#{metadata_file.id} in #{self.name}"
        array = self.data_arrays.build(name: "All Cells", cluster_name: metadata_file.name,
                                             array_type: 'cells', array_index: index + 1, values: slice,
                                             study_file_id: metadata_file.id, study_id: self.id)
        array.save
      end

      # clean up and save records
      @metadata_records.each do |metadata|
        # since first element is nil to preserve index order from file...
        unless metadata.nil?
          Rails.logger.info "#{Time.zone.now}: Saving cell metadata: #{metadata.name}-#{metadata.annotation_type} using #{metadata_file.upload_file_name}:#{metadata_file.id} in #{self.name}"
          metadata.save
        end
      end

      @metadata_data_arrays.each do |array|
        unless array.nil?
          Rails.logger.info "Saving cell metadata data array: #{array.name}-#{array.array_index} using #{metadata_file.upload_file_name}:#{metadata_file.id} in #{self.name}"
          array.save
        end
      end
      metadata_data.close
      metadata_file.update(parse_status: 'parsed')

      # set initialized to true if possible
      if self.genes.any? && self.cluster_groups.any? && !self.initialized?
        Rails.logger.info "#{Time.zone.now}: initializing #{self.name}"
        self.update(initialized: true)
        Rails.logger.info "#{Time.zone.now}: #{self.name} successfully initialized"
      end

      # assemble message
      end_time = Time.zone.now
      time = (end_time - start_time).divmod 60.0
      # assemble email message parts
      @message << "#{Time.zone.now}: #{metadata_file.upload_file_name} parse completed!"
      @message << "Entries created:"
      @metadata_records.each do |metadata|
        unless metadata.nil?
          @message << "#{metadata.name}: #{metadata.annotation_type}#{metadata.values.any? ? ' (' + metadata.values.join(', ') + ')' : nil}"
        end
      end
      @message << "Total Time: #{time.first} minutes, #{time.last} seconds"

      # load newly parsed data
      new_metadata = CellMetadatum.where(study_id: self.id, study_file_id: metadata_file.id)

      # check to make sure that all the necessary metadata-based subsample arrays exist for this study
      # if parsing first before clusters, will simply exit without performing any action and will be created when clusters are parsed
      self.cluster_groups.each do |cluster_group|
        new_metadata.each do |metadatum|
          # determine necessary subsamples
          required_subsamples = ClusterGroup::SUBSAMPLE_THRESHOLDS.select {|sample| sample < cluster_group.points}
          # for each subsample size, cluster & metadata combination, remove any existing entries and re-create
          # the delete call is necessary as we may be reparsing the file in which case the old entries need to be removed
          # if we are not reparsing, the delete call does nothing
          required_subsamples.each do |sample_size|
            DataArray.where(study_id: self.id, subsample_theshold: sample_size, subsample_annotation: "#{metadatum.name}--#{metadatum.annotation_type}--study").delete_all
            cluster_group.delay.generate_subsample_arrays(sample_size, metadatum.name, metadatum.annotation_type, 'study')
          end
        end
      end

      # check to see if default annotation has been set
      study_obj = Study.find(self.id)
      if study_obj.default_options[:annotation].nil?
        metadatum = new_metadata.first
        study_obj.default_options[:annotation] = "#{metadatum.name}--#{metadatum.annotation_type}--study"
        if metadatum.annotation_type == 'numeric'
          # set a default color profile if this is a numeric annotation
          study_obj.default_options[:color_profile] = 'Reds'
        end

        # update study.default_options
        study_obj.save
      end

      # send email on completion
      begin
        SingleCellMailer.notify_user_parse_complete(user.email, "Metadata file: '#{metadata_file.upload_file_name}' has completed parsing", @message, self).deliver_now
      rescue => e
        ErrorTracker.report_exception(e, user, error_context)
        Rails.logger.error "#{Time.zone.now}: Unable to deliver email: #{e.message}"
      end

      # set the cell count
      self.set_cell_count

      Rails.logger.info "#{Time.zone.now}: determining upload status of metadata file: #{metadata_file.upload_file_name}:#{metadata_file.id}"

      # now that parsing is complete, we can move file into storage bucket and delete local (unless we downloaded from FireCloud to begin with)
      destination = metadata_file.bucket_location
      begin
        remote = Study.firecloud_client.execute_gcloud_method(:get_workspace_file, 0, self.bucket_id, destination)
      rescue => e
        ErrorTracker.report_exception(e, user, error_context)
        Rails.logger.error "Error retrieving remote: #{e.message}"
      end
      if remote.nil?
        begin
          Rails.logger.info "#{Time.zone.now}: preparing to upload metadata file: #{metadata_file.upload_file_name}:#{metadata_file.id} to FireCloud"
          self.send_to_firecloud(metadata_file)
        rescue => e
          ErrorTracker.report_exception(e, user, error_context)
          Rails.logger.info "#{Time.zone.now}: Metadata file: #{metadata_file.upload_file_name}:#{metadata_file.id} failed to upload to FireCloud due to #{e.message}"
          SingleCellMailer.notify_admin_upload_fail(metadata_file, e.message).deliver_now
        end
      else
        # we have the file in FireCloud already, so just delete it
        begin
          Rails.logger.info "#{Time.zone.now}: found remote version of #{metadata_file.upload_file_name}: #{remote.name} (#{remote.generation})"
          run_at = 15.seconds.from_now
          Delayed::Job.enqueue(UploadCleanupJob.new(self, metadata_file, 0), run_at: run_at)
          Rails.logger.info "#{Time.zone.now}: cleanup job for #{metadata_file.upload_file_name}:#{metadata_file.id} scheduled for #{run_at}"
        rescue => e
          ErrorTracker.report_exception(e, user, error_context)
          # we don't really care if the delete fails, we can always manually remove it later as the file is in FireCloud already
          Rails.logger.error "#{Time.zone.now}: Could not delete #{metadata_file.name} in study #{self.name}; aborting"
          SingleCellMailer.admin_notification('Local file deletion failed', nil, "The file at #{@file_location} failed to clean up after parsing, please remove.").deliver_now
        end
      end
    rescue => e
      ErrorTracker.report_exception(e, user, error_context)
      # parse has failed, so clean up records and remove file
      CellMetadatum.where(study_id: self.id).delete_all
      DataArray.where(study_file_id: metadata_file.id).delete_all
      filename = metadata_file.upload_file_name
      metadata_file.remove_local_copy
      metadata_file.destroy
      error_message = "#{@last_line} ERROR: #{e.message}"
      Rails.logger.info Time.zone.now.to_s + ': ' + error_message
      SingleCellMailer.notify_user_parse_fail(user.email, "Error: Metadata file: '#{filename}' parse has failed", error_message, self).deliver_now
    end
    true
  end

  # parse precomputed marker gene files and create documents to render in Morpheus
  def initialize_precomputed_scores(marker_file, user, opts={local: true})
    begin
      error_context = ErrorTracker.format_extra_context(self, marker_file, {opts: opts})
      # remove study description as it's not useful
      error_context['study'].delete('description')
      @file_location = marker_file.upload.path
      # before anything starts, check if file has been uploaded locally or needs to be pulled down from FireCloud first
      if !opts[:local] || !marker_file.is_local?
        # make sure data dir exists first
        self.make_data_dir
        Study.firecloud_client.execute_gcloud_method(:download_workspace_file, 0, self.bucket_id, marker_file.bucket_location,
                                                     self.data_store_path, verify: :none)
        @file_location = File.join(self.data_store_path, marker_file.bucket_location)
      end

      # next, check if this is a re-parse job, in which case we need to remove all existing entries first
      if opts[:reparse]
        self.precomputed_scores.where(study_file_id: marker_file.id).delete_all
        marker_file.invalidate_cache_by_file_type
      end

      @count = 0
      @message = []
      start_time = Time.zone.now
      @last_line = ""
      @validation_error = false

      # determine content type from file contents, not from upload_content_type
      content_type = marker_file.determine_content_type
      # validate headers
      if content_type == 'application/gzip'
        Rails.logger.info "#{Time.zone.now}: Parsing #{marker_file.name}:#{marker_file.id} as application/gzip"
        file = Zlib::GzipReader.open(@file_location)
      else
        Rails.logger.info "#{Time.zone.now}: Parsing #{marker_file.name}:#{marker_file.id} as text/plain"
        file = File.open(@file_location, 'rb')
      end

      # validate headers
      headers = file.readline.split(/[\t,]/).map(&:strip)
      @last_line = "#{marker_file.name}, line 1"
      if headers.first != 'GENE NAMES' || headers.size <= 1
        marker_file.update(parse_status: 'failed')
        @validation_error = true
      end
      file.close
    rescue => e
      ErrorTracker.report_exception(e, user, error_context)
      filename = marker_file.upload_file_name
      marker_file.remove_local_copy
      marker_file.destroy
      error_message = "#{@last_line} ERROR: #{e.message}"
      Rails.logger.info Time.zone.now.to_s + ': ' + error_message
      SingleCellMailer.notify_user_parse_fail(user.email, "Error: Gene List file: '#{filename}' parse has failed", error_message, self).deliver_now
      # raise standard error to halt execution
      raise StandardError, error_message
    end

    # raise validation error if needed
    if @validation_error
      error_message = "file header validation failed: #{@last_line}: first header must be 'GENE NAMES' followed by clusters"
      filename = marker_file.upload_file_name
      marker_file.destroy
      Rails.logger.info Time.zone.now.to_s + ': ' + error_message
      SingleCellMailer.notify_user_parse_fail(user.email, "Error: Gene List file: '#{filename}' parse has failed", error_message, self).deliver_now
      raise StandardError, error_message
    end

    # begin parse
    begin
      Rails.logger.info "#{Time.zone.now}: Beginning precomputed score parse using #{marker_file.name}:#{marker_file.id} for #{self.name}"
      marker_file.update(parse_status: 'parsing')
      list_name = marker_file.name
      if list_name.nil? || list_name.blank?
        list_name = marker_file.upload_file_name.gsub(/(-|_)+/, ' ')
      end
      precomputed_score = self.precomputed_scores.build(name: list_name, study_file_id: marker_file._id)

      if content_type == 'application/gzip'
        marker_scores = Zlib::GzipReader.open(@file_location).readlines.map(&:strip).delete_if {|line| line.blank? }
      else
        marker_scores = File.open(@file_location, 'rb').readlines.map(&:strip).delete_if {|line| line.blank? }
      end

      raw_clusters = marker_scores.shift.split(/[\t,]/).map(&:strip)
      clusters = self.sanitize_input_array(raw_clusters, true)
      @last_line = "#{marker_file.name}, line 1"

      clusters.shift # remove 'Gene Name' at start
      precomputed_score.clusters = clusters
      rows = []
      # keep a running record of genes already parsed; same as expression_scores except precomputed_scores
      # have no built-in validations due to structure of gene_scores array
      @genes_parsed = []
      marker_scores.each_with_index do |line, i|
        @last_line = "#{marker_file.name}, line #{i + 2}"
        raw_vals = line.split(/[\t,]/).map(&:strip)
        vals = self.sanitize_input_array(raw_vals)
        gene = vals.shift.gsub(/\./, '_')
        if @genes_parsed.include?(gene)
          marker_file.update(parse_status: 'failed')
          user_error_message = "You have a duplicate gene entry (#{gene}) in your gene list.  Please check your file and try again."
          error_message = "Duplicate gene #{gene} in #{marker_file.name} (#{marker_file._id}) for study: #{self.name}"
          Rails.logger.info Time.zone.now.to_s + ': ' + error_message
          raise StandardError, user_error_message
        else
          # gene is unique so far so add to list
          @genes_parsed << gene
        end

        row = {"#{gene}" => {}}
        clusters.each_with_index do |cluster, index|
          row[gene][cluster] = vals[index].to_f
        end
        rows << row
        @count += 1
      end
      precomputed_score.gene_scores = rows
      precomputed_score.save
      marker_file.update(parse_status: 'parsed')

      # assemble message
      end_time = Time.zone.now
      time = (end_time - start_time).divmod 60.0
      @message << "#{Time.zone.now}: #{marker_file.name} parse completed!"
      @message << "Total gene list entries created: #{@count}"
      @message << "Total Time: #{time.first} minutes, #{time.last} seconds"
      Rails.logger.info @message.join("\n")

      # send email
      begin
        SingleCellMailer.notify_user_parse_complete(user.email, "Gene list file: '#{marker_file.name}' has completed parsing", @message, self).deliver_now
      rescue => e
        ErrorTracker.report_exception(e, user, error_context)
        Rails.logger.error "#{Time.zone.now}: Unable to deliver email: #{e.message}"
      end

      Rails.logger.info "#{Time.zone.now}: determining upload status of gene list file: #{marker_file.upload_file_name}"

      # now that parsing is complete, we can move file into storage bucket and delete local (unless we downloaded from FireCloud to begin with)
      destination = marker_file.bucket_location
      begin
        remote = Study.firecloud_client.execute_gcloud_method(:get_workspace_file, 0, self.bucket_id, destination)
      rescue => e
        ErrorTracker.report_exception(e, user, error_context)
        Rails.logger.error "Error retrieving remote: #{e.message}"
      end
      if remote.nil?
        begin
          Rails.logger.info "#{Time.zone.now}: preparing to upload gene list file: #{marker_file.upload_file_name}:#{marker_file.id} to FireCloud"
          self.send_to_firecloud(marker_file)
        rescue => e
          ErrorTracker.report_exception(e, user, error_context)
          Rails.logger.info "#{Time.zone.now}: Gene List file: #{marker_file.upload_file_name}:#{marker_file.id} failed to upload to FireCloud due to #{e.message}"
          SingleCellMailer.notify_admin_upload_fail(marker_file, e.message).deliver_now
        end
      else
        # we have the file in FireCloud already, so just delete it
        begin
          Rails.logger.info "#{Time.zone.now}: found remote version of #{marker_file.upload_file_name}: #{remote.name} (#{remote.generation})"
          run_at = 15.seconds.from_now
          Delayed::Job.enqueue(UploadCleanupJob.new(self, metadata_file, 0), run_at: run_at)
          Rails.logger.info "#{Time.zone.now}: cleanup job for #{marker_file.upload_file_name}:#{marker_file.id} scheduled for #{run_at}"
        rescue => e
          ErrorTracker.report_exception(e, user, error_context)
          # we don't really care if the delete fails, we can always manually remove it later as the file is in FireCloud already
          Rails.logger.error "#{Time.zone.now}: Could not delete #{marker_file.name} in study #{self.name}; aborting"
          SingleCellMailer.admin_notification('Local file deletion failed', nil, "The file at #{@file_location} failed to clean up after parsing, please remove.").deliver_now
        end
      end
    rescue => e
      ErrorTracker.report_exception(e, user, error_context)
      # parse has failed, so clean up records and remove file
      PrecomputedScore.where(study_file_id: marker_file.id).delete_all
      filename = marker_file.upload_file_name
      marker_file.remove_local_copy
      marker_file.destroy
      error_message = "#{@last_line} ERROR: #{e.message}"
      Rails.logger.info Time.zone.now.to_s + ': ' + error_message
      SingleCellMailer.notify_user_parse_fail(user.email, "Error: Gene List file: '#{filename}' parse has failed", error_message, self).deliver_now
    end
    true
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
      remote_file = Study.firecloud_client.execute_gcloud_method(:create_workspace_file, 0, self.bucket_id, file.upload.path,
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
      error_context = ErrorTracker.format_extra_context(self, file)
      ErrorTracker.report_exception(e, user, error_context)
      # if upload fails, try again using UploadCleanupJob in 2 minutes
      run_at = 2.minutes.from_now
      Rails.logger.error "#{Time.zone.now}: unable to upload '#{file.bucket_location}:#{file.id} to FireCloud, will retry at #{run_at}; #{e.message}"
      Delayed::Job.enqueue(UploadCleanupJob.new(file.study, file, 0), run_at: run_at)
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
    unless Dir.exists?(self.data_store_path)
      FileUtils.mkdir_p(self.data_store_path)
    end
  end

  # set the 'default_participant' entity in workspace data to allow users to upload sample information
  def set_default_participant
    begin
      path = Rails.root.join('data', self.data_dir, 'default_participant.tsv')
      entity_file = File.new(path, 'w+')
      entity_file.write "entity:participant_id\ndefault_participant"
      entity_file.close
      upload = File.open(entity_file.path)
      Study.firecloud_client.import_workspace_entities_file(self.firecloud_project, self.firecloud_workspace, upload)
      Rails.logger.info "#{Time.zone.now}: created default_participant for #{self.firecloud_workspace}"
      File.delete(path)
    rescue => e
      error_context = ErrorTracker.format_extra_context(self)
      error_context['study'].delete('description')
      ErrorTracker.report_exception(e, user, error_context)
      Rails.logger.error "#{Time.zone.now}: Unable to set default participant: #{e.message}"
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
    unless Rails.env == 'test' || self.queued_for_deletion
      if manual_set || self.public_changed? || self.new_record?
        if self.firecloud_workspace.present? && self.firecloud_project.present? && Study.read_only_firecloud_client.present?
          access_level = self.public? ? 'READER' : 'NO ACCESS'
          if !grant_access # revoke all access
            access_level = 'NO ACCESS'
          end
          Rails.logger.info "#{Time.zone.now}: setting readonly access on #{self.name} to #{access_level}"
          readonly_acl = Study.firecloud_client.create_workspace_acl(Study.read_only_firecloud_client.issuer, access_level, false, false)
          Study.firecloud_client.update_workspace_acl(self.firecloud_project, self.firecloud_workspace, readonly_acl)
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
        Study.firecloud_client.get_workspace(self.firecloud_project, self.firecloud_workspace)
      rescue RuntimeError => e
        Rails.logger.error "Marking #{self.name} as 'detached' due to missing workspace: #{self.firecloud_project}/#{self.firecloud_workspace}"
        self.update(detached: true)
      end
    end
  end

  # deletes the study and its underlying workspace.  This method is disabled in production
  def destroy_and_remove_workspace
    if Rails.env == 'production'
      return
    end
    Rails.logger.info "Removing workspace #{firecloud_project}/#{firecloud_workspace} in #{Rails.env} environment"
    begin
      Study.firecloud_client.delete_workspace(firecloud_project, firecloud_workspace)
      DeleteQueueJob.new(metadata_file).perform
      destroy
    rescue => e
      Rails.logger.error "Error in removing #{firecloud_project}/#{firecloud_workspace}"
      Rails.logger.error "#{e.class.name}:"
      Rails.logger.error "#{e.message}"
    end
    Rails.logger.info "Workspace #{firecloud_project}/#{firecloud_workspace} successfully removed."
  end

  # deletes all studies and removes all firecloud workspaces, will ONLY work if the environment is 'test' or 'pentest'
  # cannot be run in production/staging/development
  def self.delete_all_and_remove_workspaces
    if Rails.env == 'test' || Rails.env == 'pentest'
      self.all.each do |study|
        study.destroy_and_remove_workspace
      end
    end
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
          workspace = Study.firecloud_client.create_workspace(self.firecloud_project, self.firecloud_workspace)
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
          Study.firecloud_client.delete_workspace(self.firecloud_project, self.firecloud_workspace)
          errors.add(:firecloud_workspace, ' was not created properly (workspace name did not match or was not created).  Please try again later.')
          return false
        end
        Rails.logger.info "#{Time.zone.now}: Study: #{self.name} FireCloud workspace validation successful"
        # set bucket_id
        bucket = workspace['bucketName']
        self.bucket_id = bucket
        if self.bucket_id.nil?
          # delete workspace on validation fail
          Study.firecloud_client.delete_workspace(self.firecloud_project, self.firecloud_workspace)
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
          # if study project is in the compute blacklist, revoke compute permission
          if Rails.env == 'production' && FireCloudClient::COMPUTE_BLACKLIST.include?(self.firecloud_project)
            can_compute = false
          end
          acl = Study.firecloud_client.create_workspace_acl(study_owner, workspace_permission, true, can_compute)
          Study.firecloud_client.update_workspace_acl(self.firecloud_project, self.firecloud_workspace, acl)
          # validate acl
          ws_acl = Study.firecloud_client.get_workspace_acl(self.firecloud_project, ws_name)
          unless ws_acl['acl'][study_owner]['accessLevel'] == workspace_permission && ws_acl['acl'][study_owner]['canCompute'] == can_compute
            # delete workspace on validation fail
            Study.firecloud_client.delete_workspace(self.firecloud_project, self.firecloud_workspace)
            errors.add(:firecloud_workspace, ' was not created properly (permissions do not match).  Please try again later.')
            return false
          end
        end
        Rails.logger.info "#{Time.zone.now}: Study: #{self.name} FireCloud workspace acl assignment successful"
        if self.study_shares.any?
          Rails.logger.info "#{Time.zone.now}: Study: #{self.name} FireCloud workspace acl assignment for shares starting"
          self.study_shares.each do |share|
            begin
              acl = Study.firecloud_client.create_workspace_acl(share.email, StudyShare::FIRECLOUD_ACL_MAP[share.permission], true, false)
              Study.firecloud_client.update_workspace_acl(self.firecloud_project, self.firecloud_workspace, acl)
              Rails.logger.info "#{Time.zone.now}: Study: #{self.name} FireCloud workspace acl assignment for shares #{share.email} successful"
            rescue RuntimeError => e
              error_context = ErrorTracker.format_extra_context(self, acl)
              # remove study description as it's not useful
              error_context['study'].delete('description')
              ErrorTracker.report_exception(e, user, error_context)
              errors.add(:study_shares, "Could not create a share for #{share.email} to workspace #{self.firecloud_workspace} due to: #{e.message}")
              return false
            end
          end
        end

      rescue => e
        error_context = ErrorTracker.format_extra_context(self)
        # remove study description as it's not useful
        error_context['study'].delete('description')
        ErrorTracker.report_exception(e, user, error_context)
        # delete workspace on any fail as this amounts to a validation fail
        Rails.logger.info "#{Time.zone.now}: Error creating workspace: #{e.message}"
        # delete firecloud workspace unless error is 409 Conflict (workspace already taken)
        if e.message.include?("Workspace #{self.firecloud_project}/#{self.firecloud_workspace} already exists")
          errors.add(:firecloud_workspace, ' - there is already an existing workspace using this name.  Please choose another name for your study.')
          errors.add(:name, ' - you must choose a different name for your study.')
          self.firecloud_workspace = nil
        else
          Study.firecloud_client.delete_workspace(self.firecloud_project, self.firecloud_workspace)
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
        workspace = Study.firecloud_client.get_workspace(self.firecloud_project, self.firecloud_workspace)
        study_owner = self.user.email
        # set acls if using default project
        if self.firecloud_project == FireCloudClient::PORTAL_NAMESPACE
          workspace_permission = 'WRITER'
          can_compute = true
          # if study project is in the compute blacklist, revoke compute permission
          if Rails.env == 'production' && FireCloudClient::COMPUTE_BLACKLIST.include?(self.firecloud_project)
            can_compute = false
            Rails.logger.info "#{Time.zone.now}: Study: #{self.name} removing compute permissions"
            compute_acl = Study.firecloud_client.create_workspace_acl(self.user.email, workspace_permission, true, can_compute)
            Study.firecloud_client.update_workspace_acl(self.firecloud_project, self.firecloud_workspace, compute_acl)
          end
          acl = Study.firecloud_client.get_workspace_acl(self.firecloud_project, self.firecloud_workspace)
          # first check workspace authorization domain
          auth_domain = workspace['workspace']['authorizationDomain']
          unless auth_domain.empty?
            errors.add(:firecloud_workspace, ': The workspace you provided is restricted.  We currently do not allow use of restricted workspaces.  Please use another workspace.')
            return false
          end
          # check permissions
          if acl['acl'][study_owner].nil? || acl['acl'][study_owner]['accessLevel'] == 'READER'
            errors.add(:firecloud_workspace, ': You do not have write permission for the workspace you provided.  Please use another workspace.')
            return false
          end
          # check compute permissions
          if acl['acl'][study_owner]['canCompute'] != can_compute
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
              acl = Study.firecloud_client.create_workspace_acl(share.email, StudyShare::FIRECLOUD_ACL_MAP[share.permission], true, false)
              Study.firecloud_client.update_workspace_acl(self.firecloud_project, self.firecloud_workspace, acl)
              Rails.logger.info "#{Time.zone.now}: Study: #{self.name} FireCloud workspace acl assignment for shares #{share.email} successful"
            rescue RuntimeError => e
              error_context = ErrorTracker.format_extra_context(self, acl)
              # remove study description as it's not useful
              error_context['study'].delete('description')
              ErrorTracker.report_exception(e, user, error_context)
              errors.add(:study_shares, "Could not create a share for #{share.email} to workspace #{self.firecloud_workspace} due to: #{e.message}")
              return false
            end
          end
        end
      rescue => e
        error_context = ErrorTracker.format_extra_context(self)
        # remove study description as it's not useful
        error_context['study'].delete('description')
        ErrorTracker.report_exception(e, user, error_context)
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
    if Dir.exists?(self.data_store_path)
      FileUtils.rm_rf(self.data_store_path)
    end
  end

  # remove firecloud workspace on delete
  # TODO: should this be used anywhere? it's private and unused.
  def delete_firecloud_workspace
    begin
      Study.firecloud_client.delete_workspace(self.firecloud_project, self.firecloud_workspace)
    rescue RuntimeError => e
      ErrorTracker.report_exception(e, nil, {firecloud_project: self.firecloud_project, firecloud_workspace: self.firecloud_workspace})
      # workspace was not found, most likely deleted already
      Rails.logger.error "#{Time.zone.now}: #{e.message}"
    end
  end

  # set permissions on workspaces outside the portal namespace to allow users to use projects they own or are a member of
  def set_service_account_permissions
    # only perform check if this is not the default portal project
    if self.firecloud_project != FireCloudClient::PORTAL_NAMESPACE
      begin
        sa_owner_group = AdminConfiguration.find_or_create_ws_user_group!
        client = FireCloudClient.new(self.user, self.firecloud_project)
        group_email = sa_owner_group['groupEmail']
        acl = client.create_workspace_acl(group_email, 'OWNER', true, false)
        client.update_workspace_acl(self.firecloud_project, self.firecloud_workspace, acl)
        updated = client.get_workspace_acl(self.firecloud_project, self.firecloud_workspace)
        return updated['acl'][group_email]['accessLevel'] == 'OWNER'
      rescue RuntimeError => e
        ErrorTracker.report_exception(e, self.user, {firecloud_project: self.firecloud_workspace})
        Rails.logger.error "#{Time.zone.now}: unable to add portal service account to #{self.firecloud_workspace}: #{e.message}"
        false
      end
    else
      true
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
end
