# service containing business logic for managing Study registrations as datasets in DUOS
class DuosRegistrationService
  extend Loggable

  # pointer to DUOS UI for auto-completing URLs
  #
  # * *returns*
  #   - (String) DUOS UI base URL, based on environment
  def self.duos_ui_url
    Rails.env.production? ? 'https://duos.org' : 'https://duos-k8s.dsde-dev.broadinstitute.org'
  end

  # API client
  #
  # * *returns*
  #   - (DuosClient)
  def self.client
    duos_client = @client ||= DuosClient.new
    if duos_client.access_token_expired?
      duos_client.refresh_access_token!
    end
    duos_client
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
  def self.register_study(study)
    raise ArgumentError, "#{study.accession} is not eligible for DUOS registration" unless study_eligible?(study)

    begin
      dataset = client.create_dataset(study)
      ids = client.identifiers_from_dataset(dataset)
      study.update(**ids)
      log_message "Registered #{study.accession} in DUOS as #{ids}"
      dataset
    rescue ArgumentError => e
      log_message "Cannot validate #{study.accession} for DUOS: #{e.message}", level: :error
      nil
    rescue Faraday::Error => e
      log_message "Unable to register #{study.accession} in DUOS: #{e.message} (#{e.try(:response_body)})",
                  level: :error
      ErrorTracker.report_exception(e, client.issuer, { study: })
      SingleCellMailer.duos_error(study, e, 'register').deliver_now
      nil
    end
  end

  # redact a DUOS dataset registration
  # in non-production environments, this is a deletion, otherwise publicVisibility is set to false
  #
  # * *params*
  #   - +study+ (Study)
  #
  # * *returns*
  #   - (Boolean)
  def self.redact_study(study)
    return nil unless study_registered?(study)

    if Rails.env.production?
      client.update_study(study.duos_study_id, publicVisibility: false)
    else
      client.delete_study(study.duos_study_id)
      study.update(duos_dataset_id: nil, duos_study_id: nil)
    end

    log_message "Redacted #{study.accession} in DUOS"
    true
  rescue Faraday::Error => e
    log_message "Unable to redact #{study.accession} in DUOS: (#{e.message}) #{e.try(:response_body)}", level: :error
    ErrorTracker.report_exception(e, client.issuer, { study: })
    SingleCellMailer.duos_error(study, e, 'redact').deliver_now
    false
  end

  # helper to determine if a study is registered in DUOS
  # checks for presence of duos_study_id and makes API call to confirm registration
  #
  # * *params*
  #   - +study+ (Study)
  #
  # * *returns*
  #   - (Boolean)
  def self.study_registered?(study)
    return false if study.duos_study_id.blank?

    client.study(study.duos_study_id)
    true
  rescue Faraday::ResourceNotFound
    false
  end

  # helper to call on study update and deletion to manage study state in DUOS
  #
  # * *params*
  #   - +study+ (Study)
  #
  # * *returns*
  #   - (Hash) DUOS dataset registration object, if updated, otherwise nil
  def self.handle_study_update(study)
    return nil unless study_registered?(study)

    if study.public
      client.update_study(study.duos_study_id, publicVisibility: true)
    elsif study.redacted?
      redact_study(study)
    end
  end
end
