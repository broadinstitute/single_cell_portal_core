class CreateReadOnlyModeFeatureFlag < Mongoid::Migration
 def self.up
    FeatureFlag.find_or_create_by(name: 'read_only_mode') do |flag|
      flag.default_value = false
      flag.description = 'Set read-only mode to block database writes for major operations'
    end
  end

  def self.down
    flag = FeatureFlag.find_by(name: 'read_only_mode')
    flag.destroy if flag.present?
  end
end