# store author-related info for studies
# will allow users to contact study authors directly with questions if author is listed as "corresponding"
# all authors will default to corresponding: false
# can also be used for search purposes
class Author
  include Mongoid::Document
  include Mongoid::Timestamps
  field :first_name, type: String
  field :last_name, type: String
  field :email, type: String
  field :institution, type: String
  field :corresponding, type: Mongoid::Boolean, default: false
  # ORCID, global identifier for academic authors, e.g. 0000-0001-2345-6789
  field :orcid, type: String

  belongs_to :study

  validates :first_name, :last_name,
            presence: true

  validates :email,
            presence: true,
            if: proc { corresponding },
            format: {
              with: Devise.email_regexp,
              message: 'is not a valid format',
              unless: proc { email.blank? }
            }

  def base_64_email
    Base64.encode64(email)
  end

  # search definitions
  index({"first_name" => "text", "last_name" => "text", "institution" => "text"}, {background: true})
end
