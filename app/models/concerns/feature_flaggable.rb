##
# FeatureFlaggable: a module to add functionality for supporting "feature_flags" for a given model
#                   used to turn on/off special features in a sandboxed fashion
##

module FeatureFlaggable
  extend ActiveSupport::Concern

  # merges the user flags with the defaults -- this should  always be used in place of feature_flags
  # for determining whether to enable a feature for a given user.
  def feature_flags_with_defaults
    FeatureFlag.default_flag_hash.merge(self.feature_flags ? self.feature_flags : {}).with_indifferent_access
  end

  class_methods do
    # gets the feature flag value for a given instance, and the default value if no user is given
    def feature_flag_for_instance(instance, flag_key)
      if instance.present?
        instance.feature_flags_with_defaults[flag_key]
      else
        FeatureFlag.find_by(name: flag_key)&.default_value
      end
    end

    # returns feature_flags_with_defaults for the instance, or the default flags if no user is given
    def feature_flags_for_instance(instance)
      if instance.nil?
        return FeatureFlag.default_flag_hash
      end
      instance.feature_flags_with_defaults
    end
  end

  # merges feature flags of the passed-in instances from left to right,
  # using the default flag has if none of the instances is present or supplies a value
  def self.feature_flags_for_instances(*instances)
    flag_hash = FeatureFlag.default_flag_hash
    instances.each do |instance|
      if instance.present?
        flag_hash = flag_hash.merge(instance.feature_flags)
      end
    end
    flag_hash.with_indifferent_access
  end

  # updates each instance of the given model to clear the given flag
  # useful for obsoleting a given flag
  def self.remove_flag_from_model(model, flag_name)
    model.where(:"feature_flags.#{flag_name}".exists => true).each do |instance|
      instance.feature_flags.delete(flag_name)
      instance.save
    end
  end
end
