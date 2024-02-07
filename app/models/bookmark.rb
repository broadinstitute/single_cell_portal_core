class Bookmark
  include Mongoid::Document
  include Mongoid::Timestamps
  include Swagger::Blocks

  belongs_to :user
  field :name, type: String
  field :path, type: String
  field :query, type: String
  field :hash, type: String
  field :description, type: String

  validates :name, :path, presence: true, uniqueness: { scope: :user_id }
  before_validation :sanitize_path, :set_name

  swagger_schema :Bookmark do
    key :required, %i[path name user_id]
    key :name, 'SavedView'
    property :id do
      key :type, :string
    end
    property :user_id do
      key :type, :string
    end
    property :name do
      key :type, :string
      key :description, 'Name of bookmark'
    end
    property :path do
      key :type, :string
      key :description, 'URL path of bookmark'
    end
    property :query do
      key :type, :string
      key :description, 'URL query string of bookmark'
    end
    property :hash do
      key :type, :string
      key :description, 'URL hash of bookmark'
    end
    property :description do
      key :type, :string
      key :description, 'Text description of bookmark'
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

  swagger_schema :BookmarkInput do
    allOf do
      schema do
        property :bookmark do
          key :type, :object
          key :required, %i[path name]
          key :name, 'SavedView'
          property :name do
            key :type, :string
            key :description, 'Name of bookmark'
          end
          property :path do
            key :type, :string
            key :description, 'URL Path of bookmark'
          end
          property :query do
            key :type, :string
            key :description, 'URL query string of bookmark'
          end
          property :hash do
            key :type, :string
            key :description, 'URL hash of bookmark'
          end
          property :description do
            key :type, :string
            key :description, 'Text description of bookmark'
          end
        end
      end
    end
  end

  # combination of path, query string and hash to redirect browser with
  def link
    base_link = path
    base_link += "?#{query}" if query
    base_lnk += "#{hash}" if hash
  end

  # fully-qualified href, for linking
  def href
    [RequestUtils.get_base_url, path].join
  end

  private

  # default to using path for name, if not specified
  def set_name
    self.name = path if name.blank?
  end

  # only store path, query string and segment, if present
  def sanitize_path
    return nil if path.blank?

    uri = URI.parse(path.to_s)
    sanitized_path = uri.path.starts_with?('/') ? uri.path : "/#{uri.path}"
    %i[query fragment].each do |segment|
      sanitized_path += uri.send(segment) if uri.send(segment)
    end
    self.path = sanitized_path
  end
end
