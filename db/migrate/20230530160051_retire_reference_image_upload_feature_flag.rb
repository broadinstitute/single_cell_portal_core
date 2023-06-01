class RetireReferenceImageUploadFeatureFlag < Mongoid::Migration
  def self.up
    FeatureFlag.retire_feature_flag('reference_image_upload')
  end

  def self.down
  FeatureFlagMigrator.create!(name: 'reference_image_upload',
                              default_value: false,
                              description: 'allow reference image upload in the upload wizard')
  end
end
