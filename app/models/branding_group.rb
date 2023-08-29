class BrandingGroup
  include Mongoid::Document
  include Mongoid::Timestamps
  include FeatureFlaggable

  field :name, type: String
  field :name_as_id, type: String
  field :tag_line, type: String
  field :background_color, type: String, default: '#FFFFFF'
  field :font_family, type: String, default: 'Helvetica Neue, sans-serif'
  field :font_color, type: String, default: '#333333'
  field :feature_flags, type: Hash, default: {}
  field :external_link_url, type: String
  field :external_link_description, type: String
  field :public, type: Boolean, default: false

  # list of facets to show for this branding group (will restrict to only provided identifiers, if present)
  field :facet_list, type: Array, default: []

  has_and_belongs_to_many :studies
  has_and_belongs_to_many :users

  field :splash_image_file_size, type: Integer
  field :splash_image_content_type, type: String
  field :footer_image_file_size, type: Integer
  field :footer_image_content_type, type: String
  field :banner_image_file_size, type: Integer
  field :banner_image_content_type, type: String

  # carrierwave settings
  mount_uploader :splash_image, BrandingGroupImageUploader, mount_on: :splash_image_file_name
  mount_uploader :banner_image, BrandingGroupImageUploader, mount_on: :banner_image_file_name
  mount_uploader :footer_image, BrandingGroupImageUploader, mount_on: :footer_image_file_name

  # carrierwave conditional validations
  %w(splash_image banner_image footer_image).each do |image_attachment|
    validates_numericality_of "#{image_attachment}_file_size".to_sym, less_than_or_equal_to: 10.megabytes,
                              if: proc {|bg| bg.send(image_attachment).present?}
    validates_inclusion_of "#{image_attachment}_content_type",
                           in: %w(image/jpg image/jpeg image/png image/gif image/svg+xml),
                           if: proc {|bg| bg.send(image_attachment).present?}
  end

  validates_presence_of :name, :name_as_id, :background_color, :font_family
  validate :assign_curators
  validates_uniqueness_of :name
  validates_format_of :name, :name_as_id,
            with: ValidationTools::ALPHANUMERIC_SPACE_DASH, message: ValidationTools::ALPHANUMERIC_SPACE_DASH_ERROR

  validates_format_of :tag_line,
                      with: ValidationTools::OBJECT_LABELS, message: ValidationTools::OBJECT_LABELS_ERROR,
                      allow_blank: true
  validates_format_of :font_color, :font_family, :background_color, with: ValidationTools::ALPHANUMERIC_EXTENDED,
                      message: ValidationTools::ALPHANUMERIC_EXTENDED_ERROR
  before_validation :set_name_as_id
  before_destroy :remove_cached_images

  # helper to return list of associated search facets
  def facets
    self.facet_list.any? ? SearchFacet.where(:identifier.in => self.facet_list) : SearchFacet.visible
  end

  # list of curator emails
  def curator_list
    users.map(&:email)
  end

  # list of study accessions
  def study_list
    studies.map(&:accession)
  end

  # determine if user can edit branding group (all portal admins & collection curators)
  def can_edit?(user)
    !!(user && (user.admin? || users.include?(user)))
  end

  # determine if a user can destroy a branding group (only portal admins)
  def can_destroy?(user)
    !!user&.admin
  end

  private

  def set_name_as_id
    self.name_as_id = self.name.downcase.gsub(/[^a-zA-Z0-9]+/, '-').chomp('-')
  end

  # delete all cached images from UserAssetService::STORAGE_BUCKET_NAME when deleting a branding group
  def remove_cached_images
    UserAssetService.remove_assets_from_remote("branding_groups/#{self.id}")
  end

  def self.visible_groups_to_user(user)
    if user.present?
      user.visible_branding_groups
    else
      BrandingGroup.where(public: true).order_by(:name.asc)
    end
  end

  # ensure that a curator is assigned on collection creation (otherwise only admins can use it)
  def assign_curators
    errors.add(:user_ids, '- you must assign at least one curator') if user_ids.empty?
  end
end
