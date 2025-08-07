class GenomeAnnotation
  include Mongoid::Document

  belongs_to :genome_assembly
  has_many :study_files

  field :name, type: String
  field :link, type: String
  field :index_link, type: String
  field :release_date, type: Date
  field :bucket_id, type: String
  field :cloud_project, type: String

  validates_presence_of :name, :link, :index_link, :release_date
  validates_uniqueness_of :name, scope: :genome_assembly_id

  validate :set_bucket_id, :set_cloud_project, on: :create
  validate :check_genome_annotation_link
  validate :check_genome_annotation_index_link

  before_destroy :remove_study_file_associations

  ASSOCIATED_MODEL_METHOD = %w(name link index_link gs_url)
  ASSOCIATED_MODEL_DISPLAY_METHOD = %w(name genome_assembly_name species_common_name species_name species_and_assembly_name)
  OUTPUT_ASSOCIATION_ATTRIBUTE = %w(study_file_id genome_assembly_id)
  ASSOCIATION_FILTER_ATTRIBUTE = %w(name link index_link)

  def display_name
    "#{self.name} (#{self.release_date.strftime("%D")})"
  end

  # combines complete inheritance tree of taxon -> genome_assembly -> genome_annotation into one display value
  def species_and_assembly_name
    "#{self.species_common_name} (#{self.genome_assembly_name}, #{self.name})"
  end

  def genome_assembly_name
    self.genome_assembly.name
  end

  def genome_assembly_accession
    self.genome_assembly.accession
  end

  def species_common_name
    self.genome_assembly.taxon.common_name
  end

  def species_name
    self.genome_assembly.taxon.scientific_name
  end

  # generate a URL that can be accessed publicly for this genome annotation
  def public_annotation_link
    return link if link.starts_with?('http')

    begin
      client = StorageService.load_client(cloud_project:)
      client.generate_api_url(bucket_id, link)
    rescue *StorageService::HANDLED_EXCEPTIONS => e
      ErrorTracker.report_exception(e, nil, self, { method_call: :generate_api_url })
      Rails.logger.error "Cannot generate public genome annotation index link for #{index_link}: #{e.message}"
      ''
    end
  end

  # generate a URL that can be accessed publicly for this genome annotation's index
  def public_annotation_index_link
    return index_link if index_link.starts_with?('http')

    begin
      client = StorageService.load_client(cloud_project:)
      client.generate_api_url(bucket_id, index_link)
    rescue *StorageService::HANDLED_EXCEPTIONS => e
      ErrorTracker.report_exception(e, nil, self, { method_call: :generate_api_url })
      Rails.logger.error "Cannot generate public genome annotation index link for #{index_link}: #{e.message}"
      ''
    end
  end

  # generate a URL that can be used to download this annotation
  def annotation_download_link
    return link if link.starts_with?('http')

    begin
      client = StorageService.load_client(cloud_project:)
      client.generate_signed_url(bucket_id, link, expires: 15)
    rescue *StorageService::HANDLED_EXCEPTIONS => e
      ErrorTracker.report_exception(e, nil, self, { method_call: :generate_signed_url })
      Rails.logger.error "Cannot generate genome annotation download link for #{link}: #{e.message}"
      ''
    end
  end

  # construct a gs:// url for a given annotation or index
  def gs_url(link_attr=:link)
    self.bucket_id.present? ? "gs://#{self.bucket_id}/#{self.send(link_attr)}" : nil
  end

  def assign_cloud_project!
    config = AdminConfiguration.find_by(config_type: 'Reference Data Workspace')
    return if config.blank?

    reference_project, reference_workspace = config.value.split('/')
    workspace = ApplicationController.firecloud_client.get_workspace(reference_project, reference_workspace)
    cloud_project = workspace['workspace']['googleProject']
    self.cloud_project = cloud_project if cloud_project
  end

  private

  def remove_study_file_associations
    self.study_files.update_all(taxon_id: nil)
  end

  def set_cloud_project
    assign_cloud_project!
  rescue => e
    errors.add(:cloud_project, "was unable to be set due to an error: #{e.message}.")
  end

  # set the bucket ID for the reference data workspace to speed up generating GS urls, if present
  def set_bucket_id
    config = AdminConfiguration.find_by(config_type: 'Reference Data Workspace')
    if config.present?
      begin
        reference_project, reference_workspace = config.value.split('/')
        workspace = ApplicationController.firecloud_client.get_workspace(reference_project, reference_workspace)
        bucket_id = workspace['workspace']['bucketName']
        if bucket_id.present?
          self.bucket_id = bucket_id
        end
      rescue => e
        ErrorTracker.report_exception(e, genome_assembly.taxon.user,
                                      { reference_project:, reference_workspace: },
                                      self)
        errors.add(:bucket_id, "was unable to be set due to an error: #{e.message}.  Please check the reference workspace at #{config.value} and try again.")
      end
    end
  end

  # validate that the supplied genome annotation link is valid
  def check_genome_annotation_link
    if link.starts_with?('http')
      begin
        response = RestClient.get link
        unless response.code == 200
          errors.add(:link, "was not found at the specified link: #{link}.  The response code was #{response.code} rather than 200.")
        end
      rescue RestClient::Exception => e
        request_context = {
          auth_response_body: response&.body,
          auth_response_code: response&.code,
          auth_response_headers: response&.headers
        }
        ErrorTracker.report_exception(e, genome_assembly.taxon.user, request_context, self)
        errors.add(:link, "was not found due to an error: #{e.message}.  Please check the link and try again.")
      end
    else
      # assume the link is a relative path to a file in a GCS bucket
      config = AdminConfiguration.find_by(config_type: 'Reference Data Workspace')
      if config.present?
        begin
          reference_project, reference_workspace = config.value.split('/')
          client = StorageService.load_client(cloud_project:)
          unless client.bucket_file_exists?(bucket_id, link)
            errors.add(:link, "was not found in the reference workspace of #{config.value}.  Please check the link and try again.")
          end
        rescue *StorageService::HANDLED_EXCEPTIONS => e
          ErrorTracker.report_exception(e, genome_assembly.taxon.user,
                                        { reference_project:, reference_workspace: },
                                        self)
          errors.add(:link, "was not found due to an error: #{e.message}.  Please check the link and try again.")
        end
      else
        errors.add(:link, '- you have not specified a Reference Data Workspace.  Please add this via the Admin Config panel before registering a taxon.')
      end
    end
  end
end

# validate that the supplied genome annotation link is valid
def check_genome_annotation_index_link
  if index_link.starts_with?('http')
    begin
      response = RestClient.get index_link
      unless response.code == 200
        errors.add(:index_link, "was not found at the specified index link: #{index_link}.  The response code was #{response.code} rather than 200.")
      end
    rescue RestClient::Exception => e
      request_context = {
        auth_response_body: response&.body,
        auth_response_code: response&.code,
        auth_response_headers: response&.headers
      }
      ErrorTracker.report_exception(e, nil, request_context, self)
      errors.add(:index_link, "was not found due to an error: #{e.message}.  Please check the index link and try again.")
    end
  else
    # assume the link is a relative path to a file in a GCS bucket
    config = AdminConfiguration.find_by(config_type: 'Reference Data Workspace')
    if config.present?
      begin
        reference_project, reference_workspace = config.value.split('/')
        client = StorageService.load_client(cloud_project:)
        unless client.bucket_file_exists?(bucket_id, index_link)
          errors.add(:index_link, "was not found in the reference workspace of #{config.value}.  Please check the index link and try again.")
        end
      rescue *StorageService::HANDLED_EXCEPTIONS => e
        ErrorTracker.report_exception(e, genome_assembly.taxon.user,
                                      { reference_project:, reference_workspace: },
                                      self)
        errors.add(:index_link, "was not found due to an error: #{e.message}.  Please check the index link and try again.")
      end
    else
      errors.add(:index_link, '- you have not specified a Reference Data Workspace.  Please add this via the Admin Config panel before registering a taxon.')
    end
  end
end
