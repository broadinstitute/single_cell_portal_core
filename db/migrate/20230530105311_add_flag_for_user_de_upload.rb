class AddFlagForUserDeUpload < Mongoid::Migration
  def self.up
    FeatureFlag.create!(name: 'show_de_upload',
                        default_value: false,
                        description: 'show the differential expression upload tab in the upload wizard')
  end

  def self.down
    FeatureFlag.find_by(name: 'show_de_upload')&.destroy
  end
end
