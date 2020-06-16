class UserAnnotation

  extend ErrorTracker

  ###
  #
  # UserAnnotation: class holding metadata about user-defined (as opposed to study-defined) annotation objects.  Annotation
  # values are stored in child class UserDataArray
  #
  ###

  ###
  #
  # FIELD DEFINITIONS & ASSOCIATIONS
  #
  ###

  include Mongoid::Document
  extend ErrorTracker
  field :name, type: String
  field :values, type: Array
  field :queued_for_deletion, type: Boolean, default: false
  field :publishing, type: Boolean, default: false
  field :source_resolution, type: Integer

  belongs_to :user
  belongs_to :cluster_group
  belongs_to :study

  # user data arrays belong to user annotations
  has_many :user_data_arrays, dependent: :delete do
    def by_name_and_type(name, type, subsample_threshold=nil, subsample_annotation=nil)
      where(name: name, array_type: type, subsample_threshold: subsample_threshold, subsample_annotation: subsample_annotation).order_by(&:array_index).to_a
    end

    # used primarily when updating annotations to get new labels in
    def all_by_name_and_type(name, type)
      where(name: name, array_type: type).order_by(&:array_index).to_a
    end
  end

  has_many :user_annotation_shares, dependent: :delete do
    def can_edit
      where(permission: 'Edit').map(&:email)
    end

    def can_view
      all.to_a.map(&:email)
    end
  end

  accepts_nested_attributes_for :user_annotation_shares, allow_destroy: true, reject_if: proc { |attributes| attributes['email'].blank? }

  index({ user_id: 1, study_id: 1, cluster_group_id: 1, name: 1}, { unique: true, background: true })

  ###
  #
  # VALIDATIONS
  #
  ###

  # must have a name and values
  validates_presence_of :name, :values
  # unique values are name per user, study and cluster
  validates_uniqueness_of :name, scope: [:user_id, :study_id, :cluster_group_id], message: '- \'%{value}\' has already been taken.'
  validates_format_of :name, with: ValidationTools::URL_PARAM_SAFE,
                      message: ValidationTools::URL_PARAM_SAFE_ERROR

  validate :check_source_cluster_annotations

  # populate specific errors for user annotation shares since they share the same form
  validate do |user_annotation|
    user_annotation.user_annotation_shares.each do |user_annotation_share|
      next if user_annotation_share.valid?
      user_annotation_share.errors.full_messages.each do |msg|
        errors.add(:base, "Share Error - #{msg}")
      end
    end
  end

  ###
  #
  # PARSERS & CREATION METHODS
  #
  ###

  # create an annotations user data arrays
  def initialize_user_data_arrays(user_data_arrays_attributes, annotation, threshold, loaded_annotation)
    # set cluster and max length of data array
    # max length is the actual length of the annotation when not subsampled
    cluster = self.cluster_group
    max_length = cluster.points

    # handle different cases when creating annotations when different subsampling levels were selected, for creating data arrays
    case threshold
      when 1000
        # when created at a level of 1000, you have to:
        # extrapolate to a level of 10k, 20k and full data
        extrapolate(user_data_arrays_attributes, [10000, 20000], max_length, cluster, annotation)
        #and create at 1k
        create_array(cluster, 1000, annotation, user_data_arrays_attributes)
      when 10000
        # when created at a level of 10k, you have to:
        # extrapolate to a level of 20k and full data
        extrapolate(user_data_arrays_attributes, [20000], max_length, cluster, annotation)
        # create at 1000
        subsample(user_data_arrays_attributes, [1000], cluster, annotation, max_length)
        # and create at 10k
        create_array(cluster, 10000, annotation, user_data_arrays_attributes)
      when 20000
        # when created at a level of 20k, you have to:
        # extrapolate to a level of full data
        extrapolate(user_data_arrays_attributes, [], max_length, cluster, annotation)
        # subsample at 10k and 1k
        subsample(user_data_arrays_attributes, [10000, 1000],cluster, annotation, max_length)
        # and create at 20k
        create_array(cluster, 20000, annotation, user_data_arrays_attributes)
      when 100000
        # subsample at 1K, 10K, and 20K, and extrapolate to max length
        extrapolate(user_data_arrays_attributes, [], max_length, cluster, annotation)
        # subsample at 20K, 10k and 1k
        subsample(user_data_arrays_attributes, [20000, 10000, 1000],cluster, annotation, max_length)
        # and create at 20k
        create_array(cluster, 100000, annotation, user_data_arrays_attributes)
      else
        # when created at full data, aka no threshold, you have to extrapolate to full data, aka create at full data, and subsample at 100K, 20k, 10k, and 1k
        extrapolate(user_data_arrays_attributes, [], max_length, cluster, annotation)
        subsample(user_data_arrays_attributes, [100000, 20000, 10000, 1000], cluster, loaded_annotation, max_length )
    end
  end

  # combine split data arrays when they were longer than 100k values each.
  def concatenate_user_data_arrays(array_name, array_type, subsample_threshold=nil, subsample_annotation=nil)
    if subsample_threshold.blank?
      subsample_threshold = nil
      subsample_annotation = nil
    end
    # get all of the data arrays and combine them
      user_data_arrays = self.user_data_arrays.by_name_and_type(array_name, array_type, subsample_threshold, subsample_annotation)
      all_values = []
      user_data_arrays.each do |array|
        all_values += array.values
      end
      return all_values
  end

  # create a data array-- user data arrays attributes is from params follows form:
  # {label:{name=>'label' values=>'Cell1, Cell2...' } label2=>...}
  # cluster is current cluster
  def create_array(cluster, threshold, annotation, user_data_arrays_attributes)
    # create a hash of cell names of format
    # {cell_name1=>'its label', cell_name_2=>'its label'}
    user_annotation_map = {}
    user_data_arrays_attributes.keys.each do |key|
      name = user_data_arrays_attributes[key][:name]
      user_data_arrays_attributes[key][:values].split(',').each do |cell_name|
        user_annotation_map[cell_name] = name
      end
    end

    # get the cell names, x values and y values this selection was created on
    cell_name_array = cluster.concatenate_data_arrays('text', 'cells', threshold, annotation)
    x_array = cluster.concatenate_data_arrays('x', 'coordinates', threshold, annotation)
    y_array = cluster.concatenate_data_arrays('y', 'coordinates', threshold, annotation)

    # user data arrays are different than normal data arrays, so if you created a selection from a user selection this:
    # gets the cell names, x values and y values this selection was created on
    if !annotation.nil? && annotation.include?('user')
      # since user annotations can have the same name in the same cluster for different users, the lookup key is actually the ID
      user_annot_id = annotation.split('--').first
      user_annot = UserAnnotation.find(user_annot_id)
      cell_name_array = user_annot.concatenate_user_data_arrays('text', 'cells', threshold, annotation)
      x_array = user_annot.concatenate_user_data_arrays('x', 'coordinates', threshold, annotation)
      y_array = user_annot.concatenate_user_data_arrays('y', 'coordinates', threshold, annotation)
    end

    # get an ordered array of labels
    annotation_array = []
    # check if any of the values are undefined, aka this data array is being extrapolated
    undefined_happened = false

    cell_name_array.each do |name|
      cell_name = user_annotation_map[name]
      if cell_name.nil?
        cell_name = 'Undefined'
        undefined_happened = true
      end
      annotation_array << cell_name
    end


    # Create the name of the subsample annotation
    sub_an = self.formatted_annotation_identifier

    # Slice the arrays if into segments smaller than the maximum size (100k)
    x_arrays = x_array.each_slice(UserDataArray::MAX_ENTRIES).to_a
    y_arrays = y_array.each_slice(UserDataArray::MAX_ENTRIES).to_a
    cell_name_arrays = cell_name_array.each_slice(UserDataArray::MAX_ENTRIES).to_a

    # create each data array
    annotation_array.each_slice(UserDataArray::MAX_ENTRIES).each_with_index do |val, i|
      # if threshold exists then the subsample annotation and threshold need to be set on the created data array
      if threshold.present?
        Rails.logger.info "#{Time.zone.now}: Creating user annotation user data arrays with threshold: #{threshold} for name: #{self.name}"
        # Create annotation array
        UserDataArray.create!(name: self.name, array_type: 'annotations', values: val, cluster_name: cluster.name, array_index: i+1, subsample_threshold: threshold, subsample_annotation: sub_an, user_id: self.user_id, cluster_group_id: self.cluster_group_id, study_id: self.study_id, user_annotation_id: id)
        # Create X
        UserDataArray.create!(name: 'x', array_type: 'coordinates', values: x_arrays[i], cluster_name: cluster.name, array_index: i+1, subsample_threshold: threshold, subsample_annotation: sub_an, user_id: self.user_id, cluster_group_id: self.cluster_group_id, study_id: self.study_id, user_annotation_id: id )
        # Create Y
        UserDataArray.create!(name: 'y', array_type: 'coordinates', values: y_arrays[i], cluster_name: cluster.name, array_index: i+1, subsample_threshold: threshold, subsample_annotation: sub_an, user_id: self.user_id, cluster_group_id: self.cluster_group_id, study_id: self.study_id, user_annotation_id: id)
        # Create Cell Array
        UserDataArray.create!(name: 'text', array_type: 'cells', values: cell_name_arrays[i], cluster_name: cluster.name, array_index: i+1, subsample_threshold: threshold, subsample_annotation: sub_an, user_id: self.user_id, cluster_group_id: self.cluster_group_id, study_id: self.study_id, user_annotation_id: id)

      # Otherwise, if no threshold or annotation, then no threshold or annotation need to be set
      else
        Rails.logger.info "#{Time.zone.now}: Creating user annotation user data arrays without threshold for name: #{self.name}"
        # Create annotation array
        UserDataArray.create!(name: self.name, array_type: 'annotations', values: val, cluster_name: cluster.name, array_index: i+1, user_id: self.user_id, cluster_group_id: self.cluster_group_id, study_id: self.study_id, user_annotation_id: id)
        # Create X
        UserDataArray.create!(name: 'x', array_type: 'coordinates', values: x_arrays[i], cluster_name: cluster.name, array_index: i+1, user_id: self.user_id, cluster_group_id: self.cluster_group_id, study_id: self.study_id, user_annotation_id: id )
        # Create Y
        UserDataArray.create!(name: 'y', array_type: 'coordinates', values: y_arrays[i], cluster_name: cluster.name, array_index: i+1, user_id: self.user_id, cluster_group_id: self.cluster_group_id, study_id: self.study_id, user_annotation_id: id)
        # Create Cell Array
        UserDataArray.create!(name: 'text', array_type: 'cells', values: cell_name_arrays[i], cluster_name: cluster.name, array_index: i+1, user_id: self.user_id, cluster_group_id: self.cluster_group_id, study_id: self.study_id, user_annotation_id: id)
      end
    end

    # If undefined happened then the annotation these data arrays belong to needs to have undefined in its values field
    if undefined_happened
      new_values = self.values
      # Make sure not to duplicate undefined, but add it to the field values
      if !new_values.include? 'Undefined'
        new_values << 'Undefined'
        self.update(values: values)
      end
    end

  end

  # If you created a selection at a lower level, and need to view it at higher levels, you must extrapolate that selection to those levels
  # Extrapolating labels cells that were labeled at the lower level the same, and cells that weren't present in the lower level as 'Undefined'
  def extrapolate(data, thresholds, max_length, cluster, annotation)
    # full_thresh is the array of thresholds that data arrays have to be created at
    # when threshold is nil, a data array at full data is created
    # therefore, full thresh has nil by default to always create data arrays at no subsampling level
    full_thresh = [nil]

    # add thresholds to be created at, as long as the threshold isn't bigger than the size of full data, because that would be impossible
    thresholds.each do |th|
       if max_length > th
         full_thresh << th
       end
    end

    # create a data array at each threshold
    full_thresh.each do |threshold|
      create_array(cluster, threshold, annotation, data)
    end

  end

  # If you created a selection at a higher level, and need to view it at lower levels, you must subsample that selection to those levels
  # Subsampling labels cells that were labeled at the higher level the same in the lower level
  def subsample(data, thresholds, cluster, annotation, max_length)
    # create data arrays at this threshold as long as the threshold isn't bigger than the size of full data, because that would be impossible
    thresholds.each do |threshold|
      if threshold < max_length
        Rails.logger.info "Creating subsample for #{cluster.name} with #{annotation} at #{threshold}"
        create_array(cluster, threshold, annotation, data)
      end
    end
  end

  # figure out what level this annotation was created at
  # if you update an annotation's 'Undefined' level, than it will be registered as created at full data
  def subsampled_at

    arrays = self.user_data_arrays.where(array_type: 'annotations').order_by(&:subsample_threshold)
    max_length = arrays.map {|array| array.values.size}.max
    vals = self.values
    subsample_message = 'All Cells'
    # in 'Undefined' is present, then find the highest level at which it does not exist
    if vals.include? 'Undefined'
      undefined_subsamples = {}

      arrays.each do |array|
        unless array.subsample_threshold.nil?
          undefined_subsamples[array.subsample_threshold] = array.values.include? 'Undefined'
        end
      end

      # start from the lowest subsample and work up to determine what is the highest full resolution annotation &
      # maximum subsample available is
      highest_full_resolution = 1000
      max_subsample = 1000
      undefined_subsamples.keys.each do |subsample|
        highest_full_resolution = subsample if !undefined_subsamples[subsample]
        max_subsample = subsample if max_length >= subsample
      end

      # in reverse order, check if this subsample is full resolution and the max subsample available is the same
      # as the level we're checking, which means this is the level the annotation was sampled at
      [100000, 20000, 10000, 1000].each do |subsample|
        if highest_full_resolution == subsample && max_subsample == subsample
          subsample_message = subsample
        end
      end
    end
    subsample_message
  end

  def source_resolution_label
    "#{self.source_resolution.nil? ? 'All' : self.source_resolution} Cells"
  end

  def publish_to_study(current_user)
    begin
      # load original cluster group data arrays
      cluster = self.cluster_group
      annot_name = self.name
      cell_name_array = cluster.concatenate_data_arrays('text', 'cells')
      x_array = cluster.concatenate_data_arrays('x', 'coordinates')
      y_array = cluster.concatenate_data_arrays('y', 'coordinates')
      user_annotation_array = self.concatenate_user_data_arrays(annot_name,'annotations')

      # create new annotation data arrays and add them
      user_annotation_data_arrays = self.user_data_arrays.where(array_type: 'annotations').to_a
      x_arrays = self.user_data_arrays.where(array_type: 'coordinates', name: 'x').to_a
      y_arrays = self.user_data_arrays.where(array_type: 'coordinates', name: 'y').to_a
      text_arrays = self.user_data_arrays.where(array_type: 'cells').to_a
      user_annotation_data_arrays.concat(x_arrays).concat(y_arrays).concat( text_arrays)
      user_annotation_data_arrays.each do |data_array|
        if !data_array.subsample_annotation.nil?
          Rails.logger.info "#{Time.zone.now}: Creating new data array for #{annot_name} in study: #{data_array.study.name}, cluster: #{cluster.name} at subsample_threshold #{data_array.subsample_threshold}"
          subsample_annotation = annot_name + '--group--cluster'
          new_data_array = DataArray.new(name: data_array.name, cluster_name: cluster.name, array_type: data_array.array_type,
                                         array_index: data_array.array_index, values: data_array.values,
                                         subsample_annotation: subsample_annotation, subsample_threshold: data_array.subsample_threshold,
                                         study_id: cluster.study_id, study_file_id: cluster.study_file_id,
                                         linear_data_type: 'ClusterGroup', linear_data_id: cluster.id)
          if new_data_array.save
            Rails.logger.info "#{Time.zone.now}: Data Array for #{annot_name} created in study: #{data_array.study.name}, cluster: #{cluster.name}"
          else
            Rails.logger.info "#{Time.zone.now}: Data Array for #{annot_name} in study: #{data_array.study.name}, cluster: #{cluster.name} failed to save: #{new_data_array.errors.full_messages.join('; ')}"
          end
        else
          if data_array.array_type == 'annotations'
            Rails.logger.info "#{Time.zone.now}: Creating data array for #{annot_name} in study: #{data_array.study.name}, cluster: #{cluster.name}"
            new_data_array = DataArray.new(name: data_array.name, cluster_name: cluster.name, array_type: data_array.array_type,
                                           array_index: data_array.array_index, values: data_array.values,
                                           study_id: cluster.study_id, study_file_id: cluster.study_file_id,
                                           linear_data_type: 'ClusterGroup', linear_data_id: cluster.id)
            if new_data_array.save
              Rails.logger.info "#{Time.zone.now}: Data Array for #{annot_name} created in study: #{data_array.study.name}, cluster: #{cluster.name}"
            else
              Rails.logger.info "#{Time.zone.now}: Data Array for #{annot_name} in study: #{data_array.study.name}, cluster: failed to save: #{new_data_array.errors.full_messages.join('; ')}"
            end
          end
        end
      end
      # get current annotations
      cluster_annotations = cluster.cell_annotations
      cluster_annotations_array = []

      headers = ['NAME', 'X', 'Y',]
      types = ['TYPE', 'numeric', 'numeric']
      cluster_annotations.each do |annot|
        name = annot['name']
        types << annot['type']
        headers << name
        cluster_annotations_array << cluster.concatenate_data_arrays(name, 'annotations')
      end

      headers <<  annot_name
      types << 'group'

      # update cluster group cell annotation attribute with new user annotation
      annot_hash = {'name'=>annot_name, 'type'=>'group','values'=>self.values, 'header_index'=>(types.length-1)}
      Rails.logger.info "#{Time.zone.now}: Updating annotations cluster #{cluster.name} for #{annot_name} in study: #{cluster.study.name}"

      # gotcha as we must set queued for deletion to true now, otherwise the cluster_group validation will fail as it
      # will see duplicate annotation names for between cluster_group.cell_annotations & this annotation name
      # setting queued_for_deletion to true bypasses this validation

      self.update(queued_for_deletion: true)
      cluster_annotations << annot_hash

      if cluster.update(cell_annotations: cluster_annotations)
        Rails.logger.info "#{Time.zone.now}: #{cluster.name} in study: #{cluster.study.name} successfully updated, creating new source file"
        # Create new file
        study = self.study
        study_file = cluster.study_file
        # make new subdirectory for file
        subdir = File.join(study.data_store_path, study_file.id)
        if !Dir.exists?(subdir)
          FileUtils.mkdir_p(subdir)
        end
        new_file = File.new(study_file.upload.path, 'w+')

        # Write headers and types
        new_file.write(headers.join("\t")+"\n")
        new_file.write(types.join("\t") + "\n")

        # Write each row
        user_annotation_array.each_with_index do |annot, index|
          row = []
          row << cell_name_array[index]
          row << x_array[index]
          row << y_array[index]
          cluster_annotations_array.each do |cluster_annot|
            row << cluster_annot[index]
          end
          row << annot
          new_file.write(row.join("\t") +"\n")
        end
        new_file.close

        # push to FC

        Rails.logger.info "#{Time.zone.now}: new source file for #{cluster.name} in study: #{cluster.study.name} successfully created, pushing to FireCloud"
        study.send_to_firecloud(study_file)

        # queue jobs to delete annotation caches & annotation itself
        cache_key = self.cache_removal_key
        CacheRemovalJob.new(cache_key).delay(queue: :cache).perform
        DeleteQueueJob.new(self).delay.perform

        # revoke all user annotation shares
        self.user_annotation_shares.delete_all

        changes = ["User #{current_user.email} added user annotation #{annot_name} to the study #{study.name}"]

        if study.study_shares.any?
          SingleCellMailer.share_update_notification(study, changes, current_user).deliver_now
        end

      else
        # save failed, so roll back
        self.update(queued_for_deletion: false, publishing: false)

        # clean up any records that may be orphaned
        DataArray.where(name: self.name, cluster_group_id: self.cluster_group_id, array_type: 'annotations').delete_all
        Rails.logger.error("#{Time.zone.now}: Failed to update cluster cell_annotations: #{cluster.errors.full_messages.join(', ')}")

        # send notification email
        SingleCellMailer.annotation_publish_fail(self, self.user, cluster.errors.full_messages.join(', '))
      end
    rescue => e
      error_context = ErrorTracker.format_extra_context(self)
      ErrorTracker.report_exception(e, self.user, error_context)
      # error occured, so roll back
      self.update(queued_for_deletion: false, publishing: false)

      # clean up any records that may be orphaned
      DataArray.where(name: self.name, cluster_group_id: self.cluster_group_id, array_type: 'annotations').delete_all

      # send notification email
      Rails.logger.error("#{Time.zone.now}: Failed to persist user annotations: #{self.name} in study: #{self.study.name} with error: #{e.message}")
      SingleCellMailer.annotation_publish_fail(self, self.user, e.message)
    end
  end

  ###
  #
  # ACCESS CONTROL METHODS
  #
  ###

  # return all studies that are editable by a given user
  def self.editable(user)
    if user.admin?
      self.all.select {|ua| ua.valid_annotation?}
    else
      annotations = self.where(user_id: user.id).to_a.select {|ua| ua.valid_annotation?}
      shares = UserAnnotationShare.valid_user_annotations(user, 'Edit')
      [annotations + shares].flatten.uniq
    end
  end

  # return all annotations that are viewable by a given user
  def self.viewable(user)
    if user.admin?
      self.all.select {|ua| ua.valid_annotation?}
    else
      annotations = self.where(user_id: user.id).to_a.select {|ua| ua.valid_annotation?}
      shares = UserAnnotationShare.valid_user_annotations(user)
      [annotations + shares].flatten.uniq
    end
  end

  # return all annotations that are viewable to a given user for a given cluster
  def self.viewable_by_cluster(user, cluster)
    self.viewable(user).select {|ua| ua.cluster_group_id == cluster.id}
  end

  # Share Methods

  # check if a given use can edit this annotation
  def can_edit?(user)
    user.nil? ? false : self.admins.include?(user.email)
  end

  # check if a given user can view annotation by share
  def can_view?(user)
    user.nil? ? false : (self.can_edit?(user) || self.user_annotation_shares.can_view.include?(user.email))
  end

  # check if user can delete an annotation - only owners can
  def can_delete?(user)
    if user.nil?
      false
    else
      if self.user_id == user.id || user.admin?
        true
      else
        share = self.user_annotation_shares.detect {|s| s.email == user.email}
        if !share.nil? && share.permission == 'Owner'
          true
        else
          false
        end
      end
    end
  end

  # check if user can edit the study this annotation is mapped to (will check first if study has been deleted)
  def can_edit_study?(user)
    if self.study.queued_for_deletion?
      return false
    else
      return self.study.can_edit?(user)
    end
  end

  # list of emails for accounts that can edit this annotation
  def admins
    [self.user.email, self.user_annotation_shares.can_edit, User.where(admin: true).pluck(:email)].flatten.uniq
  end

  # check if an annotation is still valid (i.e. neither it nor its parent study is queued for deletion)
  def valid_annotation?
    !(self.queued_for_deletion || self.study.queued_for_deletion || self.publishing)
  end

  ###
  #
  # CACHE & DELETE METHODS
  #
  ###

  # cache lookup key used when clearing entries on updates/deletes
  def cache_removal_key
    "#{self.study.accession}/#{self.study.url_safe_name}.*#{self.cluster_group.name.split.join('-')}_#{self.formatted_annotation_identifier}"
  end

  # delete all queued annotation objects
  def self.delete_queued_annotations
    annotations = self.where(queued_for_deletion: true)
    annotations.each do |annot|
      Rails.logger.info "#{Time.zone.now} deleting queued annotation #{annot.name} in study #{annot.study.name}."
      annot.destroy
      Rails.logger.info "#{Time.zone.now} #{annot.name} successfully deleted."
    end
    true
  end

  ###
  #
  # MISCELLANEOUS METHODS
  #
  ###

  # annotation name as a DOM id
  def name_as_id
    self.name.downcase.gsub(/\s/, '-')
  end

  # get the annotation's formatted identifier (used to uniquely identify annotation when rendering/subsampling/clearing caches)
  def formatted_annotation_identifier
    "#{self.id}--group--user"
  end

  private

  # validate that the source cluster for this user annotation doesn't already have a cluster-based annotation of the same name
  def check_source_cluster_annotations
    existing_annotations = self.cluster_group.cell_annotations.map {|a| a['name']}
    if existing_annotations.include?(self.name) && !self.queued_for_deletion
      errors.add(:name, "- '#{self.name}' already exists as an annotation in the selected cluster.  Please choose a different name.")
    end
  end

end
