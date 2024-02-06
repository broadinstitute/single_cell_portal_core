class Bookmark
  include Mongoid::Document
  include Mongoid::Timestamps
  include Swagger::Blocks

  belongs_to :user
  field :name, type: String
  field :path, type: String
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
      key :description, 'Name of saved view'
    end
    property :path do
      key :type, :string
      key :description, 'URL path of saved view'
    end
    property :description do
      key :type, :string
      key :description, 'Text description of saved view'
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
            key :description, 'Name of saved view'
          end
          property :path do
            key :type, :string
            key :description, 'URL Path of saved view'
          end
          property :description do
            key :type, :string
            key :description, 'Text description of saved view'
          end
        end
      end
    end
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
