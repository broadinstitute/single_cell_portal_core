# service containing business logic for managing Study registrations as datasets in DUOS
class DuosRegistrationService

  # API client
  #
  # * *returns*
  #   - (DuosClient)
  def self.client
    @client ||= DuosClient.new
  end

  # determine if study is eligible for registering as a dataset in DUOS
  # must meet all the following criteria:
  # * public
  # * initialized
  # * has all required metadata for DUOS
  #
  # * *params*
  #   - +study+ (Study)
  #
  # * *returns*
  #   - (Boolean)
  def self.study_eligible?(study)
    has_required = required_metadata(study).map do |field, value|
      if field == :donor_count
        value > 0
      else
        value.any?
      end
    end.flatten.uniq == [true]

    study.public && study.initialized && study.duos_dataset_id.blank? && has_required
  end

  # metadata values required for DUOS dataset registration
  #
  # * *params*
  #   - +study+ (Study)
  #
  # * *returns*
  #   - (Hash)
  def self.required_metadata(study)
    {
      diseases: study.diseases,
      species: study.species_list,
      donor_count: study.donor_count,
      data_types: study.data_types
    }
  end

  # get a list of accessions for studies eligible for DUOS registration
  #
  # * *returns*
  #   - (Array<String>) list of study accessions
  def self.eligible_studies
    studies = Study.where(public: true, initialized: true, duos_dataset_id: nil, duos_study_id: nil)
    studies.select { |study| study_eligible?(study) }.map(&:accession)
  end

  # register a study as a new dataset in DUOS
  #
  #
  # * *params*
  #   - +study+ (Study)
  #
  # * *returns*
  #   - (Hash) DUOS dataset registration object
  def self.register_dataset(study)
    raise ArgumentError, "#{study.accession} is not eligible for DUOS registration" unless study_eligible?(study)

    begin
      dataset = client.create_dataset(study)
      ids = client.identifiers_from_dataset(dataset)
      study.update(**ids)
      Rails.logger.info "Registered #{study.accession} in DUOS as #{ids}"
      dataset
    rescue ArgumentError => e
      Rails.logger.error "Cannot validate #{study.accession} for DUOS: #{e.message}"
    rescue Faraday::Error => e
      Rails.logger.error "Unable to register #{study.accession} in DUOS: #{e.message} (#{e.try(:response_body)})"
      ErrorTracker.report_exception(e, client.issuer, { study: })
      nil
    end
  end

  # redact a DUOS dataset registration
  # in non-production environments, this is a deletion, otherwise publicVisiblity is set to false
  #
  # * *params*
  #   - +study+ (Study)
  #
  # * *returns*
  #   - (Boolean)
  def self.redact_dataset(study)
    client.redact_dataset(study)
    study.update(duos_dataset_id: nil, duos_study_id: nil)
    Rails.logger.info "Redacted #{study.accession} in DUOS"
    true
  rescue Faraday::Error => e
    Rails.logger.error "Unable to redact #{study.accession} in DUOS: (#{e.message}) #{e.try(:response_body)}"
    ErrorTracker.report_exception(e, client.issuer, { study: })
    false
  end
end
