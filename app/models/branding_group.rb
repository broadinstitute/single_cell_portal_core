class BrandingGroup
  include Mongoid::Document
  include Mongoid::Timestamps
  include Mongoid::Paperclip
  include FeatureFlaggable

  field :name, type: String
  field :name_as_id, type: String
  field :tag_line, type: String
  field :background_color, type: String
  field :font_family, type: String, default: 'Helvetica Neue, sans-serif'
  field :font_color, type: String, default: '#333333'
  field :feature_flags, type: Hash, default: {}

  # list of facets to show for this branding group (will restrict to only provided identifiers, if present)
  field :facet_list, type: Array, default: []

  has_many :studies
  belongs_to :user

  has_mongoid_attached_file :splash_image,
                            :path => ":rails_root/public/single_cell/branding_groups/:id/:filename",
                            :url => "/single_cell/branding_groups/:id/:filename"

  validates_attachment :splash_image,
                       content_type: { content_type: ['image/jpeg', 'image/jpg', 'image/png'] },
                       size: { in: 0..10.megabytes }

  has_mongoid_attached_file :footer_image,
                            :path => ":rails_root/public/single_cell/branding_groups/:id/:filename",
                            :url => "/single_cell/branding_groups/:id/:filename"

  validates_attachment :footer_image,
                       content_type: { content_type: ['image/jpeg', 'image/jpg', 'image/png'] },
                       size: { in: 0..10.megabytes }


  has_mongoid_attached_file :banner_image,
                            :path => ":rails_root/public/single_cell/branding_groups/:id/:filename",
                            :url => "/single_cell/branding_groups/:id/:filename"

  validates_attachment :banner_image,
                       content_type: { content_type: ['image/jpeg', 'image/jpg', 'image/png'] },
                       size: { in: 0..10.megabytes }


  validates_presence_of :name, :name_as_id, :user_id, :background_color, :font_family
  validates_uniqueness_of :name
  validates_format_of :name, :name_as_id,
            with: ValidationTools::ALPHANUMERIC_SPACE_DASH, message: ValidationTools::ALPHANUMERIC_SPACE_DASH_ERROR

  validates_format_of :tag_line,
                      with: ValidationTools::OBJECT_LABELS, message: ValidationTools::OBJECT_LABELS_ERROR,
                      allow_blank: true
  validates_format_of :font_color, :font_family, :background_color, with: ValidationTools::ALPHANUMERIC_EXTENDED,
                      message: ValidationTools::ALPHANUMERIC_EXTENDED_ERROR

  before_validation :set_name_as_id
  before_destroy :remove_branding_association

  # helper to return list of associated search facets
  def facets
    self.facet_list.any? ? SearchFacet.where(:identifier.in => self.facet_list) : SearchFacet.visible
  end

  private

  def set_name_as_id
    self.name_as_id = self.name.downcase.gsub(/[^a-zA-Z0-9]+/, '-').chomp('-')
  end

  # remove branding association on delete
  def remove_branding_association
    self.studies.each do |study|
      study.update(branding_group_id: nil)
    end
  end
end
