class RegisterEligibleDuosStudies < Mongoid::Migration
  def self.up
    registered = []
    unregistered = []
    accessions = DuosRegistrationService.eligible_studies
    puts "found #{accessions.count} eligible studies for DUOS registration"
    accessions.each do |accession|
      study = Study.find_by(accession:)
      dataset = DuosRegistrationService.register_study(study)
      if dataset
        registered << accession
      else
        unregistered << accession
      end
    end
    puts "completed!"
    puts "registered #{registered.count} studies: #{registered.join(', ')}"
    puts "failed to register #{unregistered.count} studies: #{unregistered.join(', ')}"
  end

  # don't reverse migration so we can re-run if necessary
  def self.down; end
end
