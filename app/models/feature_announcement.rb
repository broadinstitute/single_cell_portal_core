##
# Controls the display/CRUD of new feature announcement HTML blobs, similar to a blog
##
class FeatureAnnouncement
  include Mongoid::Document
  include Mongoid::Timestamps
  include Mongoid::History::Trackable
  field :title, type: String
  field :slug, type: String
  field :content, type: String
  field :doc_link, type: String
  field :published, type: Mongoid::Boolean, default: true
  field :archived, type: Mongoid::Boolean, default: false
  field :history, type: Hash, default: { published: nil, archived: nil }

  validates :title, :content, presence: true
  validates :slug, uniqueness: true, presence: true
  before_validation :set_slug
  before_save :record_latest_event

  # get a date stamp for various fields, including created_at, and history events
  def display_date(date = nil)
    case date
    when :published
      date_obj = history[:published]
    when :archived
      date_obj = history[:archived]
    else
      date_obj = created_at
    end
    date_obj&.strftime('%B %-d, %Y')
  end

  def self.published
    where(published: true)
  end

  def self.latest
    where(published: true, archived: false)
  end

  def self.archived
    where(published: true, archived: true)
  end

  # helper to hide "New feature" button on the home page if there are no published announcements
  def self.latest_features?
    latest.any?
  end

  def self.archived_features?
    archived.any?
  end

  # record the latest date of whenever an announcement is either published or archived
  # for new records, record initial state if true, otherwise only save if changed
  def record_latest_event
    %i[published archived].each do |attribute_name|
      is_changed = send("#{attribute_name}_changed?")
      is_true = send(attribute_name)
      next unless new_record? || is_changed

      history[attribute_name] = is_true ? Time.zone.today : nil
    end
  end

  # track all changes on published/archived for historical data
  track_history on: %i[published archived], modifier_field: nil

  private

  def set_slug
    if published
      published_date = history[:published] || Date.today
      # determine if we have an existing title slug we need to preserve
      # this prevents published links from breaking when the title changes
      # NOTE: unpublishing a feature will always break any published links
      if new_record? || slug&.starts_with?('unpublished-')
        title_entry = title.downcase.gsub(/[^a-zA-Z0-9]+/, '-')
      else
        title_entry = slug.split('-')[3..].join('-')
      end
      self.slug = "#{published_date.strftime('%F')}-#{title_entry.chomp('-')}"
    else
      self.slug = "unpublished-#{id}"
    end
  end
end
