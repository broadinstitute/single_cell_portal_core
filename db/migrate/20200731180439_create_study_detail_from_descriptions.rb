class CreateStudyDetailFromDescriptions < Mongoid::Migration
  def self.up
    Study.all.each do |study|
      puts "Migrating study description for #{study.accession}"
      study_detail = study.build_study_detail
      study_detail.full_description = study.description
      study_detail.save!
      puts "Migration for #{study.accession} complete"
    end
  end

  def self.down
    StudyDetail.all.each do |study_detail|
      study = study_detail.study
      puts "Resetting study description for #{study.accession}"
      study.update!(description: study_detail.full_description)
      puts "Reset for #{study.accession} complete"
    end
    StudyDetail.destroy_all
  end
end
