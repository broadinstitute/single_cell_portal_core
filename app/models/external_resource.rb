class ExternalResource
  include Mongoid::Document
  include Mongoid::Timestamps

  field :url, type: String
  field :title, type: String
  field :description, type: String
  field :publication_url, type: Mongoid::Boolean, default: false
  include Swagger::Blocks

  belongs_to :resource_links, polymorphic: true

  validates_presence_of :url, :title
  validates_uniqueness_of :title, scope: [:resource_links_id, :resource_links_type]

  swagger_schema :ExternalResource do
    key :required, [:url, :title]
    key :name, 'ExternalResource'
    property :id do
      key :type, :string
    end
    property :resource_links_id do
      key :type, :string
      key :description, 'ID of object this ExternalResource belongs to'
    end
    property :resource_links_type do
      key :type, :string
      key :description, 'Class of object this ExternalResource belongs to'
      key :enum, ['Study']
    end
    property :url do
      key :type, :string
      key :description, 'URL of external resource'
    end
    property :title do
      key :type, :string
      key :description, 'Title of external resource (used as button text)'
    end
    property :description do
      key :type, :string
      key :description, 'Text description of external resource (used as tooltip)'
    end
    property :publication_url do
      key :type, :boolean
      key :description, 'Boolean indication whether this external resource link is to a publication'
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

  swagger_schema :ExternalResourceInput do
    allOf do
      schema do
        property :external_resource do
          key :type, :object
          key :required, [:url, :title]
          property :url do
            key :type, :string
            key :description, 'URL of external resource'
          end
          property :title do
            key :type, :string
            key :description, 'Title of external resource (used as button text)'
          end
          property :description do
            key :type, :string
            key :description, 'Text description of external resource (used as tooltip)'
          end
          property :publication_url do
            key :type, :boolean
            key :description, 'Boolean indication whether this external resource link is to a publication'
          end
        end
      end
    end
  end
end
