class AddNonCompliantStudyEmailFeatureFlag < Mongoid::Migration
  def self.up
    FeatureFlag.find_or_create_by(name: 'non_compliant_study_emails') do |flag|
      flag.default_value = false
      flag.description = 'Enable sending emails to users with non-compliant studies (private and more than 1 year old)'
    end
  end

  def self.down
    flag = FeatureFlag.find_by(name: 'non_compliant_study_emails')
    flag.destroy if flag.present?
  end
end