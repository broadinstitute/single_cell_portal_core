# store publication-related data for studies
# can provide links directly to journals, along with citation information
# can also be used for search purposes
class Publication
  include Mongoid::Document
  include Mongoid::Timestamps

  field :title, type: String
  field :journal, type: String
  field :url, type: String # usually direct link to journal
  field :pmcid, type: String # PubMed Central ID
  field :citation, type: String
  field :preprint, type: Mongoid::Boolean, default: false
  include Swagger::Blocks

  belongs_to :study

  validates_presence_of :title, :journal, :url

  # generate link to PubMed Central entry
  def pmc_link
    "https://www.ncbi.nlm.nih.gov/pmc/articles/#{pmcid}"
  end

  swagger_schema :PublicationInput do
    allOf do
      schema do
        property :publication do
          key :type, :object
          key :required, [:title, :journal, :url]
          property :title do
            key :type, :string
            key :description, 'Title of Publication'
          end
          property :journal do
            key :type, :string
            key :description, 'Journal of Publication'
          end
          property :url do
            key :type, :string
            key :description, 'URL of Publication'
          end
          property :pmcid do
            key :type, :string
            key :description, 'PubMed Central ID of Publication'
          end
          property :citation do
            key :type, :string
            key :description, 'Citation of Publication'
          end
          property :preprint do
            key :type, :boolean
            key :description, 'Whether Publication is a preprint'
          end
        end
      end
    end
  end
end
