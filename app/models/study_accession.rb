class StudyAccession
  include Mongoid::Document
  include Mongoid::Timestamps

  belongs_to :study, optional: true
  field :accession, type: String

  validates_uniqueness_of :accession

  # exclude everything that does not start with "SCP" and end with digits
  ACCESSION_SANITIZER = /[^SCP\d+$]/i
  # match on accepted accession format of "SCP" and ending with digits
  ACCESSION_FORMAT = /^SCP\d+$/

  # is this accession currently assigned to an existing study?
  def assigned?
    self.study.present?
  end

  def self.next_available
    current_count = self.count
    "SCP#{current_count + 1}"
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
      accession_string = term.upcase.strip.gsub(ACCESSION_SANITIZER, '')
      if accession_string.match(ACCESSION_FORMAT)
        possible_accessions << accession_string
      end
    end
    possible_accessions
  end
end
