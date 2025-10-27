class ClusterGroup

  ###
  #
  # ClusterGroup: intermediate class that holds metadata about a 'cluster', but not actual point information (stored in DataArray)
  #
  ###

  include Mongoid::Document
  include Indexer

  field :name, type: String
  field :cluster_type, type: String
  # cell_annotations array of Hash objects with the following format
  # {
  #   name: name of annotation,
  #   type: 'group' or 'numeric',
  #   values: unique values, if group.
  #   is_differential_expression_enabled: T/F if annotation has DE outputs, default is false
  # }
  field :cell_annotations, type: Array
  field :domain_ranges, type: Hash
  field :points, type: Integer, default: 0
  # subsampling flags
  # :subsampled => whether subsampling has completed
  # :is_subsampling => whether subsampling has been initiated
  field :subsampled, type: Boolean, default: false
  field :is_subsampling, type: Boolean, default: false

  # indexing flags to control creating cluster cell index arrays
  field :indexed, type: Boolean, default: false
  field :is_indexing, type: Boolean, default: false
  field :use_default_index, type: Boolean, default: false

  # denotes when image_pipeline has been run for this cluster_group
  field :has_image_cache, type: Boolean, default: false

  validates_uniqueness_of :name, scope: :study_id
  validates_presence_of :name, :cluster_type
  validates_format_of :name, with: ValidationTools::URL_PARAM_SAFE,
                      message: ValidationTools::URL_PARAM_SAFE_ERROR

  belongs_to :study
  belongs_to :study_file

  has_many :user_annotations do
    def by_name_and_user(name, user_id)
      where(name: name, user_id: user_id, queued_for_deletion: false).first
    end
  end

  has_many :data_arrays, as: :linear_data do
    def by_name_and_type(name, type, subsample_threshold=nil)
      where(name: name, array_type: type, subsample_threshold: subsample_threshold).order_by(&:array_index).to_a
    end
  end

  has_many :differential_expression_results, dependent: :destroy

  index({ name: 1, study_id: 1 }, { unique: true, background: true })
  index({ study_id: 1 }, { unique: false, background: true })
  index({ study_id: 1, study_file_id: 1}, { unique: false, background: true })

  MAX_THRESHOLD = 100000

  # fixed values to subsample at
  SUBSAMPLE_THRESHOLDS = [MAX_THRESHOLD, 20000, 10000, 1000].freeze

  before_update :update_cluster_in_study_options

  # method to return a single data array of values for a given data array name, annotation name, and annotation value
  # gathers all matching data arrays and orders by index, then concatenates into single array
  # can also load subsample arrays by supplying optional subsample_threshold
  def concatenate_data_arrays(array_name, array_type, subsample_threshold=nil, subsample_annotation=nil)
    if subsample_threshold.nil?
      query = {
        name: array_name, array_type: array_type, linear_data_type: 'ClusterGroup', linear_data_id: self.id,
        subsample_threshold: nil, subsample_annotation: nil
      }
      DataArray.concatenate_arrays(query)
    else
      data_array = DataArray.find_by(name: array_name, array_type: array_type, linear_data_type: 'ClusterGroup',
                                     linear_data_id: self.id, subsample_threshold: subsample_threshold,
                                     subsample_annotation: subsample_annotation)
      if data_array.nil?
        # rather than returning [], default to the full resolution array
        concatenate_data_arrays(array_name, array_type)
      else
        data_array.values
      end
    end
  end

  def spatial?
    study_file&.is_spatial
  end

  def is_3d?
    self.cluster_type == '3d'
  end

  # check if user has defined a range for this cluster_group (provided in study file)
  def has_range?
    !self.domain_ranges.nil?
  end

  # check if cluster has coordinate-based annotation labels
  def has_coordinate_labels?
    DataArray.where(linear_data_id: self.id, linear_data_type: 'ClusterGroup', study_id: self.study_id,
                    array_type: 'labels').any?
  end

  # retrieve font options for coordinate labels
  def coordinate_labels_options
    {
        font_family: self.study_file.coordinate_labels_font_family,
        font_size: self.study_file.coordinate_labels_font_size,
        font_color: self.study_file.coordinate_labels_font_color
    }
  end

  # formatted annotation select option value
  def annotation_select_value(annotation, prepend_name=false)
    "#{prepend_name ? "#{self.name}--" : nil}#{annotation[:name]}--#{annotation[:type]}--" \
    "#{can_visualize_cell_annotation?(annotation) ? 'cluster' : 'invalid'}"
  end

  # return a formatted array for use in a select dropdown that corresponds to a specific cell_annotation
  def formatted_cell_annotation(annotation, prepend_name=false)
    ["#{annotation[:name]}", self.annotation_select_value(annotation, prepend_name)]
  end

  # generate a formatted select box options array that corresponds to all this cluster_group's cell_annotations
  # can be scoped to cell_annotations of a specific type (group, numeric)
  def cell_annotation_select_option(annotation_type=nil, prepend_name=false)
    annot_opts = annotation_type.nil? ? self.cell_annotations : self.cell_annotations.select {|annot| annot[:type] == annotation_type}
    annotations = annot_opts.keep_if {|annot| self.can_visualize_cell_annotation?(annot)}
    annotations.map {|annot| self.formatted_cell_annotation(annot, prepend_name)}
  end

  def cell_annotations_by_type(annotation_type=nil)
    annotation_type.nil? ? self.cell_annotations : self.cell_annotations.select {|annot| annot[:type] == annotation_type}
  end

  # list of cell annotation header values by type (group or numeric)
  def cell_annotation_names_by_type(type)
    self.cell_annotations.select {|annotation| annotation['type'] == type}.map {|annotation| annotation['name']}
  end

  # determine if this annotation is "useful" to visualize
  def can_visualize_cell_annotation?(annotation)
    return false if annotation.nil?

    annot = annotation.with_indifferent_access
    if annot[:type] == 'group'
      CellMetadatum::GROUP_VIZ_THRESHOLD === annot[:values].count ||
        self.study.override_viz_limit_annotations.include?(annot[:name])
    else
      true
    end
  end

  # whenever a cluster is updated, we need to update the study default_options ordering to reflect this
  def update_cluster_in_study_options
    return unless name_changed?

    study = self.study
    list_name = spatial? ? :spatial_order : :cluster_order
    return unless study.present? && study.default_options[list_name].present?

    old_name, new_name = name_change
    idx = study.default_options[list_name].index(old_name)
    idx ? study.default_options[list_name][idx] = new_name : study.default_options[list_name] << new_name
    study.save(validate: false) # skip validations to avoid circular dependency issues
    CacheRemovalJob.new(study.accession).delay.perform
  end

  # method used during parsing to generate representative sub-sampled data_arrays for rendering
  #
  # annotation_name: name of annotation to subsample off of
  # annotation_type: group/numeric
  # annotation_scope: cluster or study - determines where to pull metadata from to key groups off of
  def generate_subsample_arrays(sample_size, annotation_name, annotation_type, annotation_scope)
    Rails.logger.info "#{Time.zone.now}: Generating subsample data_array for cluster '#{self.name}' using annotation: #{annotation_name} (#{annotation_type}, #{annotation_scope}) at resolution #{sample_size}"
    @cells = self.concatenate_data_arrays('text', 'cells')
    case annotation_scope
      when 'cluster'
        @annotations = self.concatenate_data_arrays(annotation_name, 'annotations')
        @annotation_key = Hash[@cells.zip(@annotations)]
      when 'study'
        # in addition to array of annotation values, we need a key to preserve the associations once we sort
        # the annotations by value
        all_annots = self.study.cell_metadata.by_name_and_type(annotation_name, annotation_type).cell_annotations
        @annotation_key = {}
        @annotations = []
        @cells.each do |cell|
          @annotations << all_annots[cell]
          @annotation_key[cell] = all_annots[cell]
        end
    end

    # create a container to store subsets of arrays
    @data_by_group = {}
    # determine how many groups we have; if annotations are continuous scores, divide into 20 temporary groups
    groups = annotation_type == 'group' ? @annotations.uniq : 1.upto(20).map {|i| "group_#{i}"}
    groups.each do |group|
      @data_by_group[group] = {
          x: [],
          y: [],
          text: []
      }
      if self.is_3d?
        @data_by_group[group][:z] = []
      end
      if annotation_scope == 'cluster'
        @data_by_group[group][annotation_name.to_sym] = []
      end
    end
    raw_data = {
        text: @cells,
        x: self.concatenate_data_arrays('x', 'coordinates'),
        y: self.concatenate_data_arrays('y', 'coordinates'),
    }
    if self.is_3d?
      raw_data[:z] = self.concatenate_data_arrays('z', 'coordinates')
    end

    # divide up groups by labels (either categorical or sorted by continuous score and sliced)
    case annotation_type
      when 'group'
        @annotations.each_with_index do |annot, index|
          raw_data.each_key do |axis|
            @data_by_group[annot][axis] << raw_data[axis][index]
          end
          # we only need subsampled annotations if this is a cluster-level annotation
          if annotation_scope == 'cluster'
            @data_by_group[annot][annotation_name.to_sym] << annot
          end
        end
      when 'numeric'
        slice_size = @cells.size / groups.size
        # create a sorted array of arrays using the annotation value as the sort metric
        # first value in each sub-array is the cell name, last value is the corresponding annotation value
        sorted_annotations = @annotation_key.sort_by(&:last)
        groups.each do |group|
          sub_population = sorted_annotations.slice!(0..slice_size - 1)
          sub_population.each do |cell, annot|
            # determine where in the original source data current value resides
            original_index = @cells.index(cell)
            # store values by original_index
            raw_data.each_key do |axis|
              @data_by_group[group][axis] << raw_data[axis][original_index]
            end
            # we only need subsampled annotations if this is a cluster-level annotation
            if annotation_scope == 'cluster'
              @data_by_group[group][annotation_name.to_sym] << annot
            end
          end
        end
        # add leftovers to last group
        if sorted_annotations.size > 0
          sorted_annotations.each do |cell, annot|
            # determine where in the original source data current value resides
            original_index = @cells.index(cell)
            # store values by original_index
            raw_data.each_key do |axis|
              @data_by_group[groups.last][axis] << raw_data[axis][original_index]
            end
            # we only need subsampled annotations if this is a cluster-level annotation
            if annotation_scope == 'cluster'
              @data_by_group[groups.last][annotation_name.to_sym] << annot
            end
          end
        end
    end
    Rails.logger.info "#{Time.zone.now}: Data assembled, now subsampling for cluster '#{self.name}' using annotation: #{annotation_name} (#{annotation_type}, #{annotation_scope}) at resolution #{sample_size}"

    # determine number of entries per group required
    @num_per_group = sample_size / groups.size

    # sort groups by size
    group_order = @data_by_group.sort_by {|k,v| v[:x].size}.map(&:first)

    # build data_array objects
    data_arrays = []
    # string key that identifies how these data_arrays were assembled, will be used to query database
    # value is identical to the annotation URL query parameter when rendering clusters
    subsample_annotation = "#{annotation_name}--#{annotation_type}--#{annotation_scope}"
    raw_data.each_key do |axis|
      case axis.to_s
        when 'text'
          @array_type = 'cells'
        when annotation_name
          @array_type = 'annotations'
        else
          @array_type = 'coordinates'
      end
      data_array = self.data_arrays.build(name: axis.to_s,
                                          array_type: @array_type,
                                          cluster_name: self.name,
                                          array_index: 1,
                                          subsample_threshold: sample_size,
                                          subsample_annotation: subsample_annotation,
                                          study_file_id: self.study_file_id,
                                          study_id: self.study_id,
                                          values: []
      )
      data_arrays << data_array
    end

    # special case for cluster-based annotations
    if annotation_scope == 'cluster'
      data_array = self.data_arrays.build(name: annotation_name,
                                          array_type: 'annotations',
                                          cluster_name: self.name,
                                          array_index: 1,
                                          subsample_threshold: sample_size,
                                          subsample_annotation: subsample_annotation,
                                          study_file_id: self.study_file_id,
                                          study_id: self.study_id,
                                          values: []
      )
      data_arrays << data_array
    end

    @cells_left = sample_size

    # iterate through groups, taking requested num_per_group and recalculating as necessary
    group_order.each_with_index do |group, index|
      data = @data_by_group[group]
      # take remaining cells if last batch, otherwise take num_per_group
      requested_sample = index == group_order.size - 1 ? @cells_left : @num_per_group
      data.each do |axis, values|
        array = data_arrays.find {|a| a.name == axis.to_s}
        sample = values.shuffle(random: Random.new(1)).take(requested_sample)
        array.values += sample
      end
      # determine how many were taken in sampling pass, will either be size of requested sample
      # or all values if requested_sample is larger than size of total values for group
      cells_taken = data[:x].size > requested_sample ? requested_sample : data[:x].size
      @cells_left -= cells_taken
      # were done with this 'group', so remove from main list
      groups.delete(group)
      # recalculate num_per_group, unless last time
      unless index == group_order.size - 1
        @num_per_group = @cells_left / groups.size
      end
    end
    data_arrays.each do |array|
      array.save
    end
    Rails.logger.info "#{Time.zone.now}: Subsampling complete for cluster '#{self.name}' using annotation: #{annotation_name} (#{annotation_type}, #{annotation_scope}) at resolution #{sample_size}"
    true
  end

  # determine which subsampling levels are required for this cluster
  def subsample_thresholds_required
    SUBSAMPLE_THRESHOLDS.select {|sample| sample < self.points}
  end

  # getter method to return Mongoid::Criteria for all data arrays belonging to this cluster
  def find_all_data_arrays
    DataArray.where(study_id: self.study_id, study_file_id: self.study_file_id, linear_data_type: 'ClusterGroup', linear_data_id: self.id)
  end

  # find all 'subsampled' data arrays
  def find_subsampled_data_arrays
    self.find_all_data_arrays.where(:subsample_threshold.nin => [nil], :subsample_annotation.nin => [nil])
  end

  # control gate for invoking subsampling
  def can_subsample?
    if self.points < SUBSAMPLE_THRESHOLDS.min || self.subsampled
      false
    else
      # check if there are any data arrays belonging to this cluster that have a subsample threshold & annotation
      !self.find_subsampled_data_arrays.any?
    end
  end

  # set the point count for a cluster_group and return value
  def set_point_count!
    points = self.concatenate_data_arrays('x', 'coordinates').count
    self.update!(points: points)
    self.points
  end

  # helper to check if cell name index can be created safely
  # both the parent study file & metadata file must be parsed, and cluster is not being indexed in another process
  def can_index?
    study.metadata_file.present? && study.metadata_file.parsed? && study_file.parsed? && !indexed && !is_indexing
  end

  # index the cells from this cluster against the 'all cells' array at the study level
  # study_cells.index_with.with_index creates hash of cell names => array index position
  # averts CPU saturation of calling Array#index on very large arrays
  def cell_name_index(study_cells, subsample_annotation: nil, subsample_threshold: nil)
    cluster_cells = concatenate_data_arrays('text', 'cells', subsample_threshold, subsample_annotation)
    # if cluster cells & study cells are identical, return empty array so we can set #use_default_index
    return [] if cluster_cells == study_cells

    all_cells_hash = array_to_hashmap(study_cells)
    cluster_cells.map { |cell| all_cells_hash[cell] }
  end

  # create all necessary data array entries for cell_name_index
  def create_cell_name_index!(study_cells, subsample_annotation: nil, subsample_threshold: nil)
    cell_index = cell_name_index(study_cells, subsample_annotation:, subsample_threshold:)
    # if some cells are not indexed, don't create array as this will break things downstream
    index_count = cell_index.compact.size
    expected_cells = subsample_threshold || points
    if cell_index.empty? && subsample_threshold.nil?
      Rails.logger.info "using default cell index for #{study.accession}:#{name}"
      update!(use_default_index: true)
    elsif index_count != expected_cells
      Rails.logger.info "aborting cell index for #{study.accession}:#{name} - #{expected_cells - index_count} cells not found"
    else
      cell_index.each_slice(DataArray::MAX_ENTRIES).with_index do |slice, index|
        begin
          DataArray.create!(
            name: 'index', array_type: 'cells', array_index: index, values: slice, linear_data_type: 'ClusterGroup',
            linear_data_id: id, study_id: study.id, study_file_id:, cluster_name: name,
            subsample_annotation:, subsample_threshold:
          )
        rescue => e
          context = { job: :create_cell_name_index!, subsample_annotation:, subsample_threshold: }
          ErrorTracker.report_exception(e, nil, study, self, context)
        end
      end
    end
  end

  # create all necessary cell index arrays, both full-resolution and subsampled
  def create_all_cell_indices!
    return nil unless can_index?

    update!(is_indexing: true)
    subsampled_annotations = DataArray.where(
      study_id:, study_file_id:, subsample_threshold: 100000,
      :subsample_annotation.ne => nil, array_type: 'cells', name: 'text'
    ).pluck(:subsample_annotation, :subsample_threshold)
    all_indexes = [[nil, nil]] + subsampled_annotations
    index_query = {
      study_id:, study_file_id:, linear_data_type: 'ClusterGroup', linear_data_id: id, name: 'index',
      array_type: 'cells'
    }
    study_cells = study.all_cells_array
    all_indexes.each do |subsample_annotation, subsample_threshold|
      # skip checking full-resolution data if use_default_index is already set
      next if subsample_threshold.nil? && use_default_index

      next if DataArray.where(index_query.merge({ subsample_annotation:, subsample_threshold: })).exists?

      Rails.logger.info "creating cell name index on #{study.accession}:#{name} with " \
                        "#{subsample_annotation}:#{subsample_threshold}"
      create_cell_name_index!(study_cells, subsample_annotation:, subsample_threshold:)
    end
    # determine if any indices
    index_status = DataArray.any_of(index_query).any? || ClusterGroup.find(id).use_default_index
    update!(is_indexing: false, indexed: index_status)
  end

  # load indexed cell name array, or use default enumerator if identical to metadata file
  def cell_index_array(subsample_annotation: nil, subsample_threshold: nil)
    if subsample_annotation && subsample_threshold
      concatenate_data_arrays('index', 'cells', subsample_threshold, subsample_annotation)
    else
      use_default_index ? 0.upto(points - 1) : concatenate_data_arrays('index', 'cells')
    end
  end

  ##
  #
  # CLASS INSTANCE METHODS
  #
  ##

  def self.set_all_point_counts!
    self.all.each do |cluster|
      cluster.set_point_count!
    end
  end

  def self.generate_new_data_arrays
    start_time = Time.zone.now
    arrays_created = 0
    self.all.each do |cluster|
      arrays_to_save = []
      arrays = DataArray.where(cluster_group_id: cluster.id)
      arrays.each do |array|
        arrays_to_save << cluster.data_arrays.build(name: array.name, cluster_name: array.cluster_name, array_type: array.array_type,
                                                    array_index: array.array_index, study_id: array.study_id,
                                                    study_file_id: array.study_file_id, values: array.values,
                                                    subsample_threshold: array.subsample_threshold,
                                                    subsample_annotation: array.subsample_annotation)
      end
      arrays_to_save.map(&:save)
      arrays_created += arrays_to_save.size
    end
    end_time = Time.zone.now
    seconds_diff = (start_time - end_time).to_i.abs

    hours = seconds_diff / 3600
    seconds_diff -= hours * 3600

    minutes = seconds_diff / 60
    seconds_diff -= minutes * 60

    seconds = seconds_diff

    msg = "Cluster Group migration complete: generated #{arrays_created} new child data_array records; elapsed time: #{hours} hours, #{minutes} minutes, #{seconds} seconds"
    Rails.logger.info msg
    msg
  end
end
