class HomePageLink
  include Mongoid::Document
  include Mongoid::Timestamps

  DEFAULT_CSS_CLASS='btn btn-home-link'.freeze
  DEFAULT_BG_COLOR='#4999F9'.freeze

  field :name, type: String
  field :href, type: String
  field :tooltip, type: String
  field :bg_color, type: String, default: DEFAULT_BG_COLOR
  field :css_class, type: String, default: DEFAULT_CSS_CLASS
  field :published, type: Mongoid::Boolean, default: false
  field :image, type: String

  validates :name, :href, presence: true
  validate :ensure_one_published_link

  def publish
    update(published: true)
  end

  def unpublish
    update(published: false)
  end

  def reset_css!
    puts "Resetting css_class to '#{DEFAULT_CSS_CLASS}'"
    update(css_class: DEFAULT_CSS_CLASS)
  end

  def reset_bg_color!
    puts "Resetting css_class to '#{DEFAULT_BG_COLOR}'"
    update(bg_color: DEFAULT_BG_COLOR)
  end

  def self.published
    self.find_by(published: true)
  end

  def self.publish_last
    link = last
    if link
      puts "Publishing '#{link.name}'"
      link.publish
    else
      puts "Nothing to publish"
    end
  end

  def self.unpublish
    if published.present?
      puts "Unpublishing '#{published.name}'"
      published.update(published: false)
    else
      puts "No published links"
    end
  end

  private

  def ensure_one_published_link
    if published && HomePageLink.where(published: true, :id.ne => self.id).exists?
      existing = HomePageLink.published
      errors.add(
        :published,
        "link exists: '#{existing.name}' (#{existing.id}), please unpublish first with HomePageLink.unpublish"
      )
      puts errors.full_messages.to_sentence
    end
  end
end
