class AddPurchasesFeatureFlag < Mongoid::Migration
  def self.up
    FeatureFlag.find_or_create_by(name: 'enable_purchases_ux') do |flag|
      flag.default_value = false
      flag.description = 'Enable loading the purchases UX'
    end
  end

  def self.down
    flag = FeatureFlag.find_by(name: 'enable_purchases_ux')
    flag.destroy if flag.present?
  end
end