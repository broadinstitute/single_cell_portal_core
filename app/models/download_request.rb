# Stores information about files requested for a download and a corresponding auth. code
# Used mainly so the curl command given to users can be concise and not require excessive escape characters
class DownloadRequest

  include Mongoid::Document
  include Mongoid::Timestamps

  field :auth_code, type: String
  field :file_ids # Mongo ids of study files to download
  field :tdr_files, type: String # String representation of a hash of TDR project shortnames to arrays of access urls
  field :azul_files, type: String # String representation of a hash of Azul file summaries (Project Manifests, analysis_files, etc)
  field :user_id # User making the request

  before_save :stringify_hashes

  # This is called before the data is saved to the DB to ensure the file hashes are encoded as JSON strings
  # This is necessary to work around MongoDBs constraints on '.' and '$' in hash keys
  def stringify_hashes
    if self.azul_files.is_a?(Hash)
      self.azul_files = ActiveSupport::JSON.encode(azul_files)
    end
    if self.tdr_files.is_a?(Hash)
      self.tdr_files = ActiveSupport::JSON.encode(tdr_files)
    end
    # because these fields have type String, Rails may have already auto-converted a hash using .to_s,
    # in which case it will have Ruby-style => in it.  But we want it as json.
    self.azul_files = azul_files&.gsub('=>', ':')
    self.tdr_files = tdr_files&.gsub('=>', ':')
  end

  # decode JSON-ified TDR files back into their original array-of-hashes format
  def tdr_files_as_hash
    ActiveSupport::JSON.decode(tdr_files || '{}')
  end

  # decode JSON-ified azul files back into their original array-of-hashes format
  def azul_files_as_hash
    ActiveSupport::JSON.decode(azul_files || '{}')
  end

end
