##
# SyntheticBrandingGroupPopulator: class to populate branding groups using the output of SyntheticStudyPopulator
##

class SyntheticBrandingGroupPopulator
  BASE_BRANDING_GROUPS_CONFIG_PATH = Rails.root.join('db', 'seed', 'synthetic_branding_groups')

  # populate all branding groups using synthetic studies
  #
  # @param user (User)                 => User account to own the branding groups
  # @param create_studies (Boolean)    => Set to true to run SytheticStudyPopulator to create/overwrite studies
  def self.populate_all(user: User.first, create_studies: false)
    # populate all studies first to ensure they exist, if specified
    SyntheticStudyPopulator.populate_all if create_studies
    configurations = self.load_all_config_files
    configurations.each do |configuration|
      self.populate(configuration, user: user)
    end
  end

  # remove all synthetic branding groups, leaving studies in place
  def self.remove_all
    configurations = self.load_all_config_files
    configurations.each do |configuration|
      group_name = configuration.dig('branding_group', 'name')
      group = BrandingGroup.find_by(name: group_name)
      if group.present?
        puts "Removing branding group #{group_name}"
        group.destroy
      end
    end
  end

  # create a single branding group and associate designated studies
  #
  # @param branding_group_config (Hash)   => Configuration JSON for branding group
  # @param user (User)                    => User account to own branding group
  def self.populate(branding_group_config, user: User.first)
    puts("Populating synthetic branding group for #{branding_group_config.dig('branding_group', 'name')}")
    branding_group = self.create_branding_group(branding_group_config, user)
    # assign new branding group to all studies matching criteria
    synthetic_studies_ids = SyntheticStudyPopulator.collect_synthetic_studies.pluck(:id)
    study_regex = /#{branding_group_config.dig('study_title_regex')}/i
    study_list = Study.where(name: study_regex, :id.in => synthetic_studies_ids)
    study_list.update_all(branding_group_id: branding_group.id) if study_list.any?
  end

  private

  def self.create_branding_group(branding_group_config, user)
    existing_group = BrandingGroup.find_by(name: branding_group_config.dig('branding_group', 'name'))
    if existing_group
      puts "Destroying exiting branding group #{existing_group.name}"
      existing_group.destroy
    end

    branding_group = BrandingGroup.new(branding_group_config.dig('branding_group'))
    branding_group.user ||= user
    image_info = branding_group_config.dig('images')
    # dynamically assign image files
    image_info.each do |attribute_name, filename|
      image_file = File.open(Rails.root.join('test', 'test_data', 'branding_groups', filename))
      branding_group.send("#{attribute_name}=", image_file)
    end
    puts "Saving branding group #{branding_group.name}"
    branding_group.save!
    branding_group
  end

  def self.parse_configuration_file(config_dir)
    synthetic_group_folder = BASE_BRANDING_GROUPS_CONFIG_PATH.join(config_dir.chomp('/')).to_s
    group_info_file = File.read(File.join(synthetic_group_folder, 'branding_group_info.json'))
    JSON.parse(group_info_file)
  end

  def self.load_all_config_files
    configs_by_group = []
    group_dirs = Dir.glob(BASE_BRANDING_GROUPS_CONFIG_PATH.join('*')).select {|f| File.directory? f}
    group_dirs.each do |directory_path|
      group_config = self.parse_configuration_file(directory_path)
      configs_by_group << group_config
    end
    configs_by_group
  end
end
