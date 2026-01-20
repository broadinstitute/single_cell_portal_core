# service containing business logic for managing Study registrations as datasets in DUOS
class DuosRegistrationService

  def self.client
    @client ||= DuosClient.new
  end

  # determine if study is eligible for registering as a dataset in DUOS
  # must meet all of the following criteria:
  # * public
  # * initialized
  # * has all required metadata for DUOS
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

  def self.required_metadata(study)
    {
      diseases: study.diseases,
      species: study.species_list,
      donor_count: study.donor_count,
      data_types: study.data_types
    }
  end

  def self.register_dataset(study)
    raise ArgumentError, "#{study.accession} is not eligible for DUOS registration" unless study_eligible?(study)

    begin
      dataset = client.create_dataset(study)&.first # DUOS returns array of datasets
      study.update(duos_dataset_id: dataset[:datasetId])
      Rails.logger.info "Registered #{study.accession} in DUOS as dataset: #{dataset[:datasetId]}"
      dataset
    rescue RestClient::ExceptionWithResponse => e
      Rails.logger.error "Unable to register #{study.accession} in DUOS: #{e.message} (#{e.try(:http_body)})"
      false
    end
  end

  def self.redact_dataset(study)
    client.redact_dataset(study)
    Rails.logger.info "Redacted #{study.accession} in DUOS"
    true
  rescue RestClient::ExceptionWithResponse => e
    Rails.logger.error "Unable to redact #{study.accession} in DUOS: #{e.message} (#{e.try(:http_body)})"
    false
  end
end
