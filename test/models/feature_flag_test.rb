require 'test_helper'

class FeatureFlagTest < ActiveSupport::TestCase

  before(:all) do
    @user = FactoryBot.create(:user, test_array: @@users_to_clean)
    @branding_group = BrandingGroup.find_or_create_by!(
      name: 'Feature Flag Test', user_ids: [@user.id], font_family: 'Helvetica Neue, sans-serif',
      background_color: '#FFFFFF')
    @feature_flag = FeatureFlag.find_or_create_by!(name: 'my_feature_flag')
    @feature_flag.update!(default_value: false)
    @featurable_instances = [
      @user, @branding_group
    ]
  end

  teardown do
    # ensure clean test runs
    FeatureFlagOption.destroy_all
    @user.reload
    @branding_group.reload
    @feature_flag.ab_test&.destroy
  end

  after(:all) do
    BrandingGroup.where(name: 'Feature Flag Test').destroy_all
    # delete all testing flags, except those needed by integration tests
    FeatureFlag.where(:name.nin => %w[convention_required raw_counts_required_backend]).destroy_all
  end

  test 'should implement feature flags for included classes' do
    # use symbol instead of string to validate indifferent access
    flag_name = :my_feature_flag
    @feature_flag.update(default_value: false)

    # test defaults
    @featurable_instances.each do |instance|
      assert_not instance.feature_flags_with_defaults[flag_name],
             "Did not return false for #{instance.class} instance default flag on #{flag_name}"
      assert_not instance.feature_flag_for(flag_name),
             "Did not return false for #{instance.class} default flag on #{flag_name}"
    end

    @feature_flag.update(default_value: true)
    assert @feature_flag.default_value, "Did not update default value on #{@feature_flag.name} to true"

    # assert changes are global to all included classes & instances
    @featurable_instances.each do |instance|
      assert instance.feature_flags_with_defaults[flag_name],
             "Did not return true for #{instance.class} instance default flag on #{flag_name}"
      assert instance.feature_flag_for(flag_name),
             "Did not return true for #{instance.class} default flag on #{flag_name}"

      # assert locals override defaults
      instance.set_flag_option(flag_name, false)
      assert_not instance.feature_flags_with_defaults[flag_name],
             "Did not return false for #{instance.class} instance override flag on #{flag_name}"
      assert_not instance.feature_flag_for(flag_name),
             "Did not return false for #{instance.class} individual instance override flag on #{flag_name}"
    end
  end

  test 'feature flaggable merges instance flags correctly' do
    flag_name = :my_feature_flag
    @feature_flag.update!(default_value: true)

    assert FeatureFlaggable.feature_flags_for_instances(nil, nil)[flag_name]
    assert FeatureFlaggable.feature_flags_for_instances(@branding_group, @user)[flag_name]

    @branding_group.set_flag_option(flag_name, false)
    assert_not FeatureFlaggable.feature_flags_for_instances(@branding_group, nil)[flag_name]
    assert_not FeatureFlaggable.feature_flags_for_instances(@branding_group, @user)[flag_name]

    @user.set_flag_option(flag_name, true)
    assert FeatureFlaggable.feature_flags_for_instances(@branding_group, @user)[flag_name]
    # check the merge is order-sensitive
    assert_not FeatureFlaggable.feature_flags_for_instances(@user, @branding_group)[flag_name]
  end

  test 'should find overrides for specific feature flags' do
    flag_name = :override_flag
    FeatureFlag.create(name: flag_name.to_s, default_value: false)
    assert_not FeatureFlaggable.flag_override_for_instances(flag_name, true, @user)
    assert_not FeatureFlaggable.flag_override_for_instances(flag_name, true, @user, @branding_group)
    # assert that override same as default value always returns false, since there's no override in effect
    assert_not FeatureFlaggable.flag_override_for_instances(flag_name, false, @user)
    @user.set_flag_option(flag_name, true)
    assert FeatureFlaggable.flag_override_for_instances(flag_name, true, @user)
    assert FeatureFlaggable.flag_override_for_instances(flag_name, true, @user, @branding_group)
  end

  test 'should merge values across instances for feature flag' do
    flag_name = :merged_value_for_flag
    FeatureFlag.create(name: flag_name.to_s, default_value: false)
    assert_not FeatureFlaggable.merged_value_for(flag_name, nil)
    assert_not FeatureFlaggable.merged_value_for(flag_name, @branding_group)
    @branding_group.set_flag_option(flag_name, true)
    assert FeatureFlaggable.merged_value_for(flag_name, @branding_group)
    assert FeatureFlaggable.merged_value_for(flag_name, @branding_group, @user)
    @user.set_flag_option(flag_name, false)
    assert_not FeatureFlaggable.merged_value_for(flag_name, @branding_group, @user)
  end

  test 'should retire feature flag' do
    flag_name = :new_flag
    FeatureFlag.create(name: flag_name.to_s, default_value: false)
    @user.set_flag_option(flag_name, true)
    assert @user.feature_flag_for(flag_name)
    FeatureFlag.retire_feature_flag(flag_name)
    assert_nil @user.feature_flag_for(flag_name)
    assert_nil FeatureFlag.find_by(name: flag_name)
  end

  test 'should get and set FeatureFlagOption instances' do
    flag_name = :saving_flags
    FeatureFlag.create(name: flag_name.to_s, default_value: false)
    assert_not @user.feature_flag_for(flag_name)
    flag_as_hash = { flag_name => false }.with_indifferent_access
    assert_equal flag_as_hash, @user.feature_flag_as_hash(flag_name)
    @user.set_flag_option(flag_name, true)
    assert @user.feature_flag_for(flag_name)
    flag_option = @user.get_flag_option(flag_name)
    assert flag_option.present?
    assert_equal flag_option.to_h, @user.feature_flag_as_hash(flag_name)
  end

  test 'should remove FeatureFlagOption instances' do
    flag_name = :deleting_flags
    FeatureFlag.create(name: flag_name.to_s, default_value: false)
    @user.set_flag_option(flag_name, true)
    assert @user.feature_flag_for(flag_name)
    # remove_flag_option will return true when flag is configured
    assert @user.remove_flag_option(flag_name)
    assert_not @user.feature_flag_for(flag_name)
    # this will now return false, as no operation happened
    assert_not @user.remove_flag_option(flag_name)
  end

  test 'should get requested feature flags as hash' do
    flags = %w[feature_flag_1 feature_flag_2 feature_flag_3]
    flags.each_with_index do |flag_name, index|
      FeatureFlag.create(name: flag_name.to_s, default_value: index.odd?)
    end
    expected_flags = {
      feature_flag_1: false,
      feature_flag_2: true,
      feature_flag_3: false
    }.with_indifferent_access
    assert_equal expected_flags, @user.feature_flags_for(*flags)
    @user.set_flag_option(:feature_flag_1, true)
    updated_flags = {
      feature_flag_1: true,
      feature_flag_2: true,
      feature_flag_3: false
    }.with_indifferent_access
    assert_equal updated_flags, @user.feature_flags_for(*flags)
  end

  test 'should only return configured flags' do
    flags = %w[configured_flag unconfigured_flag]
    flags.each do |flag_name|
      FeatureFlag.create(name: flag_name.to_s, default_value: true)
    end
    @user.set_flag_option(:configured_flag, false)
    expected_output = {
      configured_flag: false
    }.with_indifferent_access
    assert_equal expected_output, @user.configured_feature_flags
    @user.remove_flag_option(:configured_flag)
    @user.reload
    assert_empty @user.configured_feature_flags
  end

  test 'should merge in _destroy param on defaults' do
    flag_name = :params_test
    FeatureFlag.create(name: flag_name.to_s, default_value: false)
    @user.set_flag_option(flag_name, true)
    option = @user.get_flag_option(flag_name)
    params = {
      FeatureFlaggable::NESTED_FORM_KEY => {
        '0' => option.form_attributes
      }
    }.with_indifferent_access
    # should not update as value is explicitly set
    updated_params = FeatureFlaggable.merge_default_destroy_param(params)
    assert_equal params, updated_params
    # mimic "default" selection of empty value
    params[FeatureFlaggable::NESTED_FORM_KEY]['0'][:value] = ''
    updated_params = FeatureFlaggable.merge_default_destroy_param(params)
    assert_equal '1', updated_params[FeatureFlaggable::NESTED_FORM_KEY]['0'][:_destroy]
  end

  test 'should find enabled A/B test' do
    assert_not @feature_flag.ab_test_enabled?
    AbTest.create(feature_flag: @feature_flag, enabled: true)
    assert @feature_flag.ab_test_enabled?
  end
end
