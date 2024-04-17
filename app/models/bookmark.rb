# Book of particular SCP page
class Bookmark
  include Mongoid::Document
  include Mongoid::Timestamps
  include Swagger::Blocks
  include FlatId

  belongs_to :user
  field :name, type: String
  field :path, type: String
  field :study_accession, type: String
  field :description, type: String

  validates :name, :path, presence: true, uniqueness: { scope: %i[user_id study_accession] }
  before_validation :sanitize_path, :set_name

  swagger_schema :Bookmark do
    key :required, %i[path name user_id]
    key :name, 'Bookmark'
    property :_id do
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
    property :study_accession do
      key :type, :string
      key :description, 'Accession of associated study'
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
          key :name, 'Bookmark'
          property :name do
            key :type, :string
            key :description, 'Name of bookmark'
          end
          property :path do
            key :type, :string
            key :description, 'URL Path of bookmark, including query string/hash'
          end
          property :study_accession do
            key :type, :string
            key :description, 'Accession of associated study'
          end
          property :description do
            key :type, :string
            key :description, 'Text description of bookmark'
          end
        end
      end
    end
  end

  private

  # default to using path for name, if not specified
  def set_name
    self.name = path if name.blank?
  end

  # only store path, query string and fragment (including delimiters), if present
  def sanitize_path
    return nil if path.blank?

    uri = URI.parse(path.to_s)
    sanitized_path = uri.path.starts_with?('/') ? uri.path : "/#{uri.path}"
    # append delimiter and url segment, if present
    { query: '?', fragment: '#' }.each do |segment, delimiter|
      sanitized_path += "#{delimiter}#{uri.send(segment)}" if uri.send(segment)
    end
    self.path = sanitized_path
  end
end
