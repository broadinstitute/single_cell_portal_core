class StudyAccession
  include Mongoid::Document
  include Mongoid::Timestamps

  belongs_to :study, optional: true
  field :accession, type: String

  validates_uniqueness_of :accession

  # exclude everything that does not start with "SCP" and end with digits
  ACCESSION_SANITIZER = /[^SCP\d+$]/
  # match on accepted accession format of "SCP" and ending with digits
  ACCESSION_FORMAT = /^SCP\d+$/

  # is this accession currently assigned to an existing study?
  def assigned?
    self.study.present?
  end

  def self.next_available_id
    current_count = self.count
    "SCP#{current_count + 1}"
  end

  def self.create_for_study(study)
    # if there is an accession attached use that
    # this is only allowed in non-production environments to allow persistent accessions for synth studies
    if !Rails.env.production? && study.accession
      existing_accession = StudyAccession.find_by!(accession: study.accession)
      existing_accession.update!(study_id: study.id)
      return existing_accession
    else # otherwise just grab the next accession
      next_accession_id = StudyAccession.next_available_id
      # sanity check in case multiple studies are being created at the same time
      while Study.where(accession: next_accession_id).exists? || StudyAccession.where(accession: next_accession_id).exists?
        next_accession_id = StudyAccession.next_available_id
      end
      return StudyAccession.create(accession: next_accession_id, study_id: study.id)
    end
  end


  def self.assign_accessions
    Study.all.each do |study|
      puts "Assigning accession for #{study.name}"
      study.assign_accession
      puts "Accession for #{study.name} assigned: #{study.accession}"
    end
  end

  # sanitize an list of terms to format as a StudyAccession
  def self.sanitize_accessions(terms)
    possible_accessions = []
    terms.each do |term|
      accession_string = term.strip.gsub(ACCESSION_SANITIZER, '')
      if accession_string.match(ACCESSION_FORMAT)
        possible_accessions << accession_string
      end
    end
    possible_accessions
  end
end
