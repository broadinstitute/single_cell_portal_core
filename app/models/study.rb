class Study
  include Mongoid::Document
  include Mongoid::Timestamps

  # pagination
  def self.per_page
    5
  end

  # associations and scopes
  belongs_to :user
  has_many :study_files, dependent: :destroy do
    def by_type(file_type)
      if file_type.is_a?(Array)
        where(:file_type.in => file_type).to_a
      else
        where(file_type: file_type).to_a
      end
    end
  end
  has_many :cluster_points, dependent: :destroy
  has_many :single_cells, dependent: :destroy
  has_many :expression_scores, dependent: :destroy do
    def by_gene(gene)
      where(gene: gene).first
    end
  end

  has_many :precomputed_scores, dependent: :destroy do
    def by_name(name)
      where(name: name).first
    end
  end

  has_many :study_shares, dependent: :destroy do
    def can_edit
      where(permission: 'Edit').map(&:email)
    end

    def can_view
      all.to_a.map(&:email)
    end
  end

  has_many :cluster_groups, dependent: :destroy
  has_many :data_arrays, dependent: :destroy do
    def by_name_and_type(name, type)
      where(name: name, array_type: type).order_by(&:array_index).to_a
    end
  end

  has_many :clusters, dependent: :destroy do
    def parent_clusters
      where(cluster_type: 'parent').to_a.delete_if {|c| c.cluster_points.empty? }
    end

    def sub_cluster(name)
      where(parent_cluster: name).to_a.delete_if {|c| c.cluster_points.empty? }
    end
  end

  has_many :study_metadatas, dependent: :destroy do
    def by_name_and_type(name, type)
      where(name: name, annotation_type: type).to_a
    end
  end

  # field definitions
  field :name, type: String
  field :embargo, type: Date
  field :url_safe_name, type: String
  field :description, type: String
  field :public, type: Boolean, default: true
  field :initialized, type: Boolean, default: false
  field :view_count, type: Integer, default: 0
  field :cell_count, type: Integer, default: 0
  field :view_order, type: Float, default: 100.0

  accepts_nested_attributes_for :study_files, allow_destroy: true
  accepts_nested_attributes_for :study_shares, allow_destroy: true, reject_if: proc { |attributes| attributes['email'].blank? }

  validates_uniqueness_of :name
  validates_presence_of :name

  # populate specific errors for study shares since they share the same form
  validate do |study|
    study.study_shares.each do |study_share|
      next if study_share.valid?
      study_share.errors.full_messages.each do |msg|
        errors.add(:base, "Share Error: #{msg}")
      end
    end
  end

  # callbacks
  before_save     :set_url_safe_name
  before_update   :check_data_links
  after_save      :check_public?
  before_destroy  :remove_public_symlinks
  after_destroy   :remove_data_dir

  # search definitions
  index({"name" => "text", "description" => "text"})

  # return all studies that are editable by a given user
  def self.editable(user)
    studies = self.where(user_id: user._id).to_a
    shares = StudyShare.where(email: user.email, permission: 'Edit').map(&:study)
    [studies + shares].flatten.uniq
  end

  # return all studies that are viewable by a given user
  def self.viewable(user)
    public = self.where(public: true).map(&:_id)
    owned = self.where(user_id: user._id, public: false).map(&:_id)
    shares = StudyShare.where(email: user.email).map(&:study_id)
    intersection = public + owned + shares
    # return Mongoid criterion object to use with pagination
    Study.in(:_id => intersection)
  end

  # check if a give use can edit study
  def can_edit?(user)
    self.admins.include?(user.email)
  end

  # check if a given user can view study by share (does not take public into account - use Study.viewable(user) instead)
  def can_view?(user)
    self.can_edit?(user) || self.study_shares.can_view.include?(user.email)
  end

  # list of emails for accounts that can edit this study
  def admins
    [self.user.email, self.study_shares.can_edit].flatten.uniq
  end

  # file path to study public folder
  def data_public_path
    Rails.root.join('public', 'single_cell', 'data', self.url_safe_name)
  end

  # file path to upload storage directory
  def data_store_path
    Rails.root.join('data', self.url_safe_name)
  end

  # label for study visibility
  def visibility
    self.public? ? "<span class='sc-badge bg-success text-success'>Public</span>".html_safe : "<span class='sc-badge bg-danger text-danger'>Private</span>".html_safe
  end

  # check whether or not user has uploaded necessary files to parse cluster coords.
  # DEPRECATED
  def can_parse_clusters
    self.study_files.size > 1 && self.study_files.where(file_type:'Cluster Assignments').exists? && self.study_files.where(file_type:'Cluster Coordinates').exists?
  end

  # check if study is still under embargo or whether given user can bypass embargo
  def embargoed?(user)
    if user.nil?
      self.check_embargo
    else
      # must not be viewable by current user & embargoed to be true
      !self.can_view?(user) && self.check_embargo
    end
  end

  # helper method to check embargo status
  def check_embargo
    self.embargo.nil? || self.embargo.blank? ? false : Date.today <= self.embargo
  end

  # helper method to get number of unique single cells
  def set_cell_count
    @cell_count = 0
    if self.expression_matrix_file.nil? && !self.single_cells.empty?
      @cell_count = self.single_cells.uniq!(&:name).count
    elsif !self.expression_matrix_file.nil?
      file = File.open(self.expression_matrix_file.upload.path)
      cells = file.readline.split(/[\t,]/)
      file.close
      cells.shift
      @cell_count = cells.size
    end
    self.update(cell_count: @cell_count)
  end

  # return an array of all single cell names in study
  def all_cells
    cell_arrays = self.data_arrays.where(name: 'All Cells').order('array_index asc').to_a
    all_values = []
    cell_arrays.each do |array|
      all_values += array.values
    end
    all_values
  end

  # return a hash keyed by cell name of the requested study_metadata values
  def study_metadata_values(metadata_name, metadata_type)
    metadata_objects = self.study_metadatas.by_name_and_type(metadata_name, metadata_type)
    vals = {}
    metadata_objects.each do |metadata|
      vals.merge!(metadata.cell_annotations)
    end
    vals
  end

  # return array of possible values for a given study_metadata annotation (only for group-based)
  def study_metadata_keys(metadata_name, metadata_type)
    vals = []
    unless metadata_type == 'numeric'
      metadata_objects = self.study_metadatas.by_name_and_type(metadata_name, metadata_type)
      metadata_objects.each do |metadata|
        vals += metadata.values
      end
    end
    vals.uniq
  end

  # helper to build a study file of the requested type
  def build_study_file(attributes)
    self.study_files.build(attributes)
  end

  # helper method to access all cluster definitions files
  def cluster_ordinations_files
    self.study_files.where(file_type: 'Cluster').to_a
  end

  # helper method to access cluster definitions file by name
  def cluster_ordinations_file(name)
    self.study_files.where(file_type: 'Cluster', name: name).first
  end

  # helper method to directly access expression matrix file
  def expression_matrix_file
    self.study_files.where(file_type:'Expression Matrix').first
  end

  # helper method to directly access expression matrix file
  def metadata_file
    self.study_files.where(file_type:'Metadata').first
  end

  # method to parse master expression scores file for study and populate collection
  def make_expression_scores(expression_file, user=nil)
    @count = 0
    @bytes_parsed = 0
    @message = []
    @last_line = ""
    start_time = Time.now
    @validation_error = false

    # validate headers
    begin
      file = File.open(expression_file.upload.path)
      cells = file.readline.strip.split(/[\t,]/)
      @last_line = "#{expression_file.name}, line 1"
      if !['gene', ''].include?(cells.first.downcase) || cells.size <= 1
        expression_file.update(parse_status: 'failed')
        @validation_error = true
      end
      file.close
    rescue => e
      expression_file.update(parse_status: 'failed')
      error_message = "Unexpected error: #{e.message}"
      Rails.logger.info @last_line + ' ' + error_message
      raise StandardError, error_message
    end

    # raise validation error if needed
    if @validation_error
      error_message = "file header validation failed: #{@last_line}; first header should be GENE or blank followed by cell names"
      Rails.logger.info error_message
      raise StandardError, error_message
    end

    # begin parse
    begin
      Rails.logger.info "Beginning expression score parse from #{expression_file.name} for #{self.name}"
      expression_file.update(parse_status: 'parsing')
      # open data file and grab header row with name of all cells, deleting 'GENE' at start
      expression_data = File.open(expression_file.upload.path)
      cells = expression_data.readline.strip.split(/[\t,]/)
      @last_line = "#{expression_file.name}, line 1: #{cells.join("\t")}"

      cells.shift
      # store study id for later to save memory
      study_id = self._id
      @records = []
      # keep a running record of genes already parsed to catch validation errors before they happen
      # this is needed since we're creating records in batch and won't know which gene was responsible
      @genes_parsed = []
      Rails.logger.info "Expression scores loaded, starting record creation for #{self.name}"
      while !expression_data.eof?
        # grab single row of scores, parse out gene name at beginning
        line = expression_data.readline.strip
        row = line.split(/[\t,]/)
        @last_line = "#{expression_file.name}, line #{expression_data.lineno}"

        gene_name = row.shift

        # convert all remaining strings to floats, then store only significant values (!= 0)
        scores = row.map(&:to_f)
        significant_scores = {}
        scores.each_with_index do |score, index|
          unless score == 0.0
            significant_scores[cells[index]] = score
          end
        end
        # create expression score object
        @records << {gene: gene_name, scores: significant_scores, study_id: study_id, study_file_id: expression_file._id}
        @bytes_parsed += line.length
        @count += 1
        if @count % 1000 == 0
          ExpressionScore.create(@records)
          expression_file.update(bytes_parsed: @bytes_parsed)
          @records = []
          Rails.logger.info "Processed #{@count} expression scores from #{expression_file.name} for #{self.name}"
        end
      end
      ExpressionScore.create!(@records)
      # create array of all cells for study
      @cell_data_array = self.data_arrays.build(name: 'All Cells', array_type: 'cells', array_index: 1, study_file_id: expression_file._id)
      # chunk into pieces as necessary
      cells.each_slice(DataArray::MAX_ENTRIES) do |slice|
        new_array_index = @cell_data_array.array_index + 1
        @cell_data_array.values = slice
        Rails.logger.info "Saving all cells data array ##{@cell_data_array.array_index} using #{expression_file.name} for #{self.name}"
        @cell_data_array.save
        @cell_data_array = self.data_arrays.build(name: 'All Cells', array_type: 'cells', array_index: new_array_index, study_file_id: expression_file._id)
      end

      # clean up, print stats
      expression_data.close
      expression_file.update(parse_status: 'parsed', bytes_parsed: expression_file.upload_file_size)
      end_time = Time.now
      time = (end_time - start_time).divmod 60.0
      @message << "#{expression_file.name} parse completed!"
      @message << "ExpressionScores created: #{@count}"
      @message << "Total Time: #{time.first} minutes, #{time.last} seconds"
      Rails.logger.info @message.join("\n")
      # set initialized to true if possible
      if !self.cluster_ordinations_files.empty? && !self.metadata_file.nil? && !self.initialized?
        self.update(initialized: true)
      end
      unless user.nil?
        SingleCellMailer.notify_user_parse_complete(user.email, "Expression file: '#{expression_file.name}' has completed parsing", @message).deliver_now
      end
    rescue => e
      expression_file.update(parse_status: 'failed')
      error_message = "#{@last_line} ERROR: #{e.message}"
      Rails.logger.info error_message
      raise StandardError, error_message
    end
    true
  end

  # parse single cluster coordinate & metadata file (name, x, y, z, metadata_cols* format)
  # uses cluster_group model instead of single clusters; group membership now defined by metadata
  # stores point data in cluster_group_data_arrays instead of single_cells and cluster_points
  def initialize_cluster_group_and_data_arrays(ordinations_file)
    # validate headers of definition file
    @validation_error = false
    begin
      d_file = File.open(ordinations_file.upload.path)
      headers = d_file.readline.split(/[\t,]/).map(&:strip)
      second_header = d_file.readline.split(/[\t,]/).map(&:strip)
      @last_line = "#{ordinations_file.name}, line 1"
      # must have at least NAME, X and Y fields
      unless (headers & %w(NAME X Y)).size == 3 && second_header.include?('TYPE')
        ordinations_file.update(parse_status: 'failed')
        @validation_error = true
      end
      d_file.close
    rescue => e
      ordinations_file.update(parse_status: 'failed')
      error_message = "Unexpected error: #{e.message}"
      Rails.logger.info @last_line + ' ' + error_message
      raise StandardError, error_message
    end

    # raise validation error if needed
    if @validation_error
      error_message = "file header validation failed: #{@last_line}; should be at least NAME, X, Y with second line starting with TYPE"
      Rails.logger.info error_message
      raise StandardError, error_message
    end

    @bytes_parsed = 0
    @update_chunk = ordinations_file.upload_file_size / 4.0
    @current_chunk = 0
    @cluster_metadata = []
    @records = []
    # begin parse
    begin
      cluster_name = ordinations_file.name
      Rails.logger.info "Beginning cluster initialization using #{ordinations_file.upload_file_name} for cluster: #{cluster_name} in #{self.name}"

      cluster_data = File.open(ordinations_file.upload.path)
      header_data = cluster_data.readline.split(/[\t,]/).map(&:strip)
      type_data = cluster_data.readline.split(/[\t,]/).map(&:strip)

      # determine if 3d coordinates have been provided
      is_3d = header_data.include?('Z')
      cluster_type = is_3d ? '3d' : '2d'

      # grad header indices, z index will be nil if no 3d data
      name_index = header_data.index('NAME')
      x_index = header_data.index('X')
      y_index = header_data.index('Y')
      z_index = header_data.index('Z')

      # determine what extra metadata has been provided
      metadata_headers = header_data - %w(NAME X Y Z)
      metadata_headers.each do |metadata|
        idx = header_data.index(metadata)
        # store temporary object with metadata name, index location and data type (group or numeric)
        point_metadata = {
            name: metadata,
            index: idx,
            type: type_data[idx].downcase # downcase type to avoid case matching issues later
        }
        @cluster_metadata << point_metadata
      end

      # create cluster object for use later
      Rails.logger.info "Creating cluster group object: #{cluster_name} in study: #{self.name}"
      @cluster_group = self.cluster_groups.build(name: cluster_name, study_file_id: ordinations_file._id, cluster_type: cluster_type)

      # add cell-level annotation definitions and save (will be used to populate dropdown menu)
      # this object will not be saved until after parse is done as we need to collect all possible values
      # for group annotations (not needed for numeric)
      cell_annotations = []
      @cluster_metadata.each do |metadata|
        cell_annotations << {
            name: metadata[:name],
            type: metadata[:type],
            header_index: metadata[:index],
            values: []
        }
      end
      @cluster_group.save

      # container to store temporary data arrays until ready to save
      @data_arrays = []
      # create required data_arrays (name, x, y)
      @data_arrays[name_index] = self.data_arrays.build(name: 'text', cluster_name: cluster_name, array_type: 'cells', array_index: 1, study_file_id: ordinations_file._id, cluster_group_id: @cluster_group._id, values: [])
      @data_arrays[x_index] = self.data_arrays.build(name: 'x', cluster_name: cluster_name, array_type: 'coordinates', array_index: 1, study_file_id: ordinations_file._id, cluster_group_id: @cluster_group._id, values: [])
      @data_arrays[y_index] = self.data_arrays.build(name: 'y', cluster_name: cluster_name, array_type: 'coordinates', array_index: 1, study_file_id: ordinations_file._id, cluster_group_id: @cluster_group._id, values: [])

      # add optional data arrays (z, metadata)
      if is_3d
        @data_arrays[z_index] = self.data_arrays.build(name: 'z', cluster_name: cluster_name, array_type: 'coordinates', array_index: 1, study_file_id: ordinations_file._id, cluster_group_id: @cluster_group._id, values: [])
      end
      @cluster_metadata.each do |metadata|
        @data_arrays[metadata[:index]] = self.data_arrays.build(name: metadata[:name], cluster_name: cluster_name, array_type: 'annotations', array_index: 1, study_file_id: ordinations_file._id, cluster_group_id: @cluster_group._id, values: [])
      end

      Rails.logger.info "Headers/Metadata loaded for cluster initialization using #{ordinations_file.upload_file_name} for cluster: #{cluster_name} in #{self.name}"
      # begin reading data
      while !cluster_data.eof?
        line = cluster_data.readline.strip
        @last_line = "#{ordinations_file.name}, line #{cluster_data.lineno}"
        vals = line.split(/[\t,]/).map(&:strip)
        # assign value to corresponding data_array by column index
        vals.each_with_index do |val, index|
          if @data_arrays[index].values.size >= DataArray::MAX_ENTRIES
            # array already has max number of values, so save it and replace it with a new data array
            # of same name & type with array_index incremented by 1
            current_data_array_index = @data_arrays[index].array_index
            data_array = @data_arrays[index]
            Rails.logger.info "Saving data array: #{data_array.name}-#{data_array.array_type}-#{data_array.array_index} using #{ordinations_file.upload_file_name} for cluster: #{cluster_name} in #{self.name}"
            data_array.save
            new_data_array = self.data_arrays.build(name: data_array.name, cluster_name: data_array.cluster_name ,array_type: data_array.array_type, array_index: current_data_array_index + 1, study_file_id: ordinations_file._id, cluster_group_id: @cluster_group._id, values: [])
            @data_arrays[index] = new_data_array
          end
          # determine whether or not value needs to be cast as a float or not
          if type_data[index] == 'numeric'
            @data_arrays[index].values << val.to_f
          else
            @data_arrays[index].values << val
            # check if this is a group annotation, and if so store its value in the cluster_group.cell_annotations
            # hash if the value is not already present
            if type_data[index] == 'group'
              existing_vals = cell_annotations.select {|annot| annot[:name] == header_data[index]}.first
              metadata_idx = cell_annotations.index(existing_vals)
              unless existing_vals[:values].include?(val)
                cell_annotations[metadata_idx][:values] << val
                Rails.logger.info "Adding #{val} to #{@cluster_group.name} list of group values for #{header_data[index]}"
              end
            end
          end
        end
        @bytes_parsed += line.length
        @current_chunk += line.length
        # since parsing happens quickly, only update status in ~25% increments
        # updating after every line slows down parsing
        if @current_chunk / @update_chunk > 1
          ordinations_file.update(bytes_parsed: @bytes_parsed)
          @current_chunk = 0
        end
      end
      # clean up
      @data_arrays.each do |data_array|
        Rails.logger.info "Saving data array: #{data_array.name}-#{data_array.array_type}-#{data_array.array_index} using #{ordinations_file.upload_file_name} for cluster: #{cluster_name} in #{self.name}"
        data_array.save
      end
      cluster_data.close

      # save cell_annotations to cluster_group object
      @cluster_group.update_attributes(cell_annotations: cell_annotations)

      ordinations_file.update(parse_status: 'parsed', bytes_parsed: ordinations_file.upload_file_size)
      # set initialized to true if possible
      if !self.expression_matrix_file.nil? && !self.metadata_file.nil? && !self.initialized?
        self.update(initialized: true)
      end
    rescue => e
      ordinations_file.update(parse_status: 'failed')
      error_message = "#{@last_line} ERROR: #{e.message}"
      Rails.logger.info error_message
      raise StandardError, error_message
    end
    true
  end

  # parse a study metadata file and create necessary study_metadata objects
  # study_metadata objects are hashes that store annotations in cell_name/annotation_value pairs
  # call @study.study_metadata_values(metadata_name, metadata_type) to return all values as one hash
  def initialize_study_metadata(metadata_file, user=nil)
    # validate headers of definition file
    @validation_error = false
    begin
      Rails.logger.info "Validating metadata file headers for #{metadata_file.name} in #{self.name}"
      m_file = File.open(metadata_file.upload.path)
      headers = m_file.readline.split(/[\t,]/).map(&:strip)
      @last_line = "#{metadata_file.name}, line 1"
      second_header = m_file.readline.split(/[\t,]/).map(&:strip)
      @last_line = "#{metadata_file.name}, line 2"
      # must have at least NAME and one column, plus TYPE and one value of group or numeric in second line
      unless headers.include?('NAME') && headers.size > 1 && (second_header.uniq.sort - %w(group numeric TYPE)).size == 0 && second_header.size > 1
        metadata_file.update(parse_status: 'failed')
        @validation_error = true
      end
      m_file.close
    rescue => e
      metadata_file.update(parse_status: 'failed')
      error_message = "Unexpected error: #{e.message}"
      Rails.logger.info @last_line + ' ' + error_message
      raise StandardError, error_message
    end

    # raise validation error if needed
    if @validation_error
      error_message = "file header validation failed: #{@last_line}; should be at least NAME and one other column with second line starting with TYPE followed by either 'group' or 'numeric'"
      Rails.logger.info error_message
      raise StandardError, error_message
    end

    @bytes_parsed = 0
    @current_chunk = 0
    @update_chunk = metadata_file.upload_file_size / 4.0
    @metadata_records = []
    # begin parse
    begin
      Rails.logger.info "Beginning metadata initialization using #{metadata_file.upload_file_name} in #{self.name}"

      # open files for parsing and grab header & type data
      metadata_data = File.open(metadata_file.upload.path)
      header_data = metadata_data.readline.split(/[\t,]/).map(&:strip)
      type_data = metadata_data.readline.split(/[\t,]/).map(&:strip)
      name_index = header_data.index('NAME')

      # build study_metadata objects for use later
      header_data.each_with_index do |header, index|
        # don't need an object for the cell names, only metadata values
        unless index == name_index
          m_obj = self.study_metadatas.build(name: header, annotation_type: type_data[index], study_file_id: metadata_file._id, cell_annotations: {}, values: [])
          @metadata_records[index] = m_obj
        end
      end

      Rails.logger.info "Study metadata objects initialized using: #{metadata_file.name} for #{self.name}; beginning parse"
      # read file data
      while !metadata_data.eof?
        line = metadata_data.readline.strip
        @last_line = "#{metadata_file.name}, line #{metadata_data.lineno}"
        vals = line.split(/[\t,]/).map(&:strip)

        # assign values to correct study_metadata object
        vals.each_with_index do |val, index|
          unless index == name_index
            if @metadata_records[index].cell_annotations.size >= StudyMetadata::MAX_ENTRIES
              # study metadata already has max number of values, so save it and replace it with a new study_metadata of same name & type
              metadata = @metadata_records[index]
              Rails.logger.info "Saving study metadata: #{metadata.name}-#{metadata.annotation_type} using #{metadata_file.upload_file_name} in #{self.name}"
              metadata.save
              new_metadata = self.study_metadatas.build(name: metadata.name, annotation_type: metadata.annotation_type, study_file_id: metadata_file._id, cell_annotations: {}, values: [])
              @metadata_records[index] = new_metadata
            end
            # determine whether or not value needs to be cast as a float or not
            if type_data[index] == 'numeric'
              @metadata_records[index].cell_annotations.merge!({"#{vals[name_index]}" => val.to_f})
            else
              @metadata_records[index].cell_annotations.merge!({"#{vals[name_index]}" => val})
              # determine if a new unique value needs to be stored in values array
              if type_data[index] == 'group' && !@metadata_records[index].values.include?(val)
                @metadata_records[index].values << val
                Rails.logger.info "Adding #{val} to #{@metadata_records[index].name} list of group values for #{header_data[index]}"
              end
            end
          end
        end
        # since parsing happens quickly, only update status in ~25% increments
        # updating after every line slows down parsing
        if @current_chunk / @update_chunk > 1
          metadata_file.update(bytes_parsed: @bytes_parsed)
          @current_chunk = 0
        end
      end
      # clean up
      @metadata_records.each do |metadata|
        # since first element is nil to preserve index order from file...
        unless metadata.nil?
          Rails.logger.info "Saving study metadata: #{metadata.name}-#{metadata.annotation_type} using #{metadata_file.upload_file_name} in #{self.name}"
          metadata.save
        end
      end
      metadata_data.close
      metadata_file.update(parse_status: 'parsed', bytes_parsed: metadata_file.upload_file_size)

      # set initialized to true if possible
      if !self.expression_matrix_file.nil? && !self.cluster_ordinations_files.empty? && !self.initialized?
        self.update(initialized: true)
      end
    rescue => e
      metadata_file.update(parse_status: 'failed')
      error_message = "#{@last_line} ERROR: #{e.message}"
      Rails.logger.info error_message
      raise StandardError, error_message
    end
    true
  end

  # parse precomputed marker gene files and create documents to render in Morpheus
  def make_precomputed_scores(marker_file, user=nil)
    @count = 0
    @message = []
    start_time = Time.now
    @last_line = ""
    @validation_error = false

    # validate headers
    begin
      file = File.open(marker_file.upload.path)
      headers = file.readline.strip.split(/[\t,]/)
      @last_line = "#{marker_file.name}, line 1"
      if headers.first != 'GENE NAMES' || headers.size <= 1
        marker_file.update(parse_status: 'failed')
        @validation_error = true
      end
      file.close
    rescue => e
      marker_file.update(parse_status: 'failed')
      error_message = "Unexpected error: #{e.message}"
      Rails.logger.info @last_line + ' ' + error_message
      raise StandardError, error_message
    end

    # raise validation error if needed
    if @validation_error
      error_message = "file header validation failed: #{@last_line}: first header must be 'GENE NAMES' followed by clusters"
      Rails.logger.info error_message
      raise StandardError, error_message
    end

    # begin parse
    begin
      Rails.logger.info "Beginning precomputed score parse using #{marker_file.name} for #{self.name}"
      marker_file.update(parse_status: 'parsing')
      list_name = marker_file.name
      if list_name.nil? || list_name.blank?
        list_name = marker_file.upload_file_name.gsub(/(-|_)+/, ' ')
      end
      precomputed_score = self.precomputed_scores.build(name: list_name, study_file_id: marker_file._id)
      marker_scores = File.open(marker_file.upload.path).readlines.map(&:strip).delete_if {|line| line.blank? }
      clusters = marker_scores.shift.split(/[\t,]/)
      @last_line = "#{marker_file.name}, line 1"

      clusters.shift # remove 'Gene Name' at start
      precomputed_score.clusters = clusters
      rows = []
      # keep a running record of genes already parsed; same as expression_scores except precomputed_scores
      # have no built-in validations due to structure of gene_scores array
      @genes_parsed = []
      marker_scores.each_with_index do |line, i|
        @last_line = "#{marker_file.name}, line #{i + 2}"
        vals = line.split(/[\t,]/)
        gene = vals.shift
        uniq_gene_name = gene.downcase
        if @genes_parsed.include?(uniq_gene_name)
          marker_file.update(parse_status: 'failed')
          user_error_message = "You have a duplicate gene entry (#{gene}) in your gene list.  Please check your file and try again."
          error_message = "Duplicate gene #{gene} in #{marker_file.name} (#{marker_file._id}) for study: #{self.name}"
          Rails.logger.info error_message
          raise StandardError, user_error_message
        else
          # gene is unique so far so add to list
          @genes_parsed << uniq_gene_name
        end

        row = {"#{gene}" => {}}
        clusters.each_with_index do |cluster, index|
          row[gene][cluster] = vals[index].to_f
        end
        rows << row
        @count += 1
      end
      precomputed_score.gene_scores = rows
      precomputed_score.save
      marker_file.update(parse_status: 'parsed', bytes_parsed: marker_file.upload_file_size)
      end_time = Time.now
      time = (end_time - start_time).divmod 60.0
      @message << "#{marker_file.name} parse completed!"
      @message << "Total scores created: #{@count}"
      @message << "Total Time: #{time.first} minutes, #{time.last} seconds"
      Rails.logger.info @message.join("\n")
      unless user.nil?
        SingleCellMailer.notify_user_parse_complete(user.email, "Gene list file: '#{marker_file.name}' has completed parsing", @message).deliver_now
      end
    rescue => e
      marker_file.update(parse_status: 'failed')
      error_message = "#{@last_line} ERROR: #{e.message}"
      Rails.logger.info error_message
      raise StandardError, error_message
    end
    true
  end

  # one-time helper to reformat files of an older type into newer current form with 2 header lines
  # preserves old file as .bak for disaster recovery
  def reformat_study_file(study_file)
    orig_file = File.open(study_file.upload.path)
    new_file_name = study_file.upload.path + '.new'
    new_file = File.new(new_file_name, 'w+')
    # double logging for persistence
    message = "Opening #{study_file.upload_file_name} in #{self.name} for reading, writing new data to #{new_file_name}"
    Rails.logger.info message
    puts message
    while !orig_file.eof?
      line = orig_file.readline
      # write correct new header information based on file type
      if orig_file.lineno == 1
        vals = line.split(/[\t,]/).map(&:strip)
        name_index = vals.index('CELL_NAME')
        vals[name_index] = 'NAME'
        new_file.puts vals.join("\t")
        if study_file.file_type == 'Cluster Assignments'
          new_file.puts "TYPE\tgroup\tgroup"
        elsif study_file.file_type == 'Cluster Coordinates'
          new_file.puts "TYPE\tnumeric\tnumeric"
        end
      else
        # write rest of contents
        new_file.puts line
      end
    end
    # clean up
    orig_file.close
    new_file.close
    # move old file to .bak, then new file to original filename
    message = "Write complete, moving  #{study_file.upload.path} to #{study_file.upload.path + '.bak'} in #{self.name}"
    Rails.logger.info message
    puts message
    FileUtils.mv study_file.upload.path, study_file.upload.path + '.bak'
    message = "Finishing up, moving  #{new_file_name} to #{study_file.upload.path} in #{self.name}"
    Rails.logger.info message
    puts message
    FileUtils.mv study_file.upload.path + '.new', study_file.upload.path
    # update file type accordingly
    new_file_type = study_file.file_type == 'Cluster Assignments' ? 'Metadata' : 'Cluster'
    message = "Updating file type of #{study_file.upload.path} to #{new_file_type} in #{self.name}"
    Rails.logger.info message
    puts message
    study_file.update_attributes(file_type: new_file_type)
    true
  end

  # Single-use method to migrate all studies without study_metadata or data_arrays into new collections
  def self.migrate_all_studies
    # collect all studies and determine which need to be migrated - will have both single_cells and cluster_points
    self.all.to_a.each do |study|
      if study.single_cells.any? && study.cluster_points.any?
        message = "Beginning migration for #{study.name}"
        Rails.logger.info message
        puts message
        # cluster assignments & coordinates files need to be re-formatted & re-parsed
        eligible_files = study.study_files.where(file_type: /(Coordinates|Assignments)/).to_a
        message = "Found #{eligible_files.size} eligible files: #{eligible_files.map(&:upload_file_name).join(', ')}"
        Rails.logger.info message
        puts message
        # re-format and re-parse all matching files
        eligible_files.each do |file|
          message = "Beginning reformatting of #{file.upload_file_name}"
          Rails.logger.info message
          puts message
          study.reformat_study_file(file)
          # reload file to make sure we have updated attributes
          new_file = StudyFile.find(file._id)
          # re-parse file to populate database
          message = "Beginning re-parsing of #{new_file.upload_file_name}"
          Rails.logger.info message
          puts message
          case new_file.file_type
            when 'Metadata'
              message = "Parsing #{new_file.upload_file_name} as #{new_file.file_type}"
              Rails.logger.info message
              puts message
              study.initialize_study_metadata(new_file)
            when 'Cluster'
              message = "Parsing #{new_file.upload_file_name} as #{new_file.file_type}"
              Rails.logger.info message
              puts message
              study.initialize_cluster_group_and_data_arrays(new_file)
            else
              puts "Ineligible file type for #{new_file.upload_file_name}: #{new_file.file_type}; skipping parse"
          end
          message = "Parsing of #{new_file.upload_file_name} complete"
          Rails.logger.info message
          puts message
        end
        message = "Migration complete for #{study.name}"
        Rails.logger.info message
        puts message
      end
    end
    message = "All eligible studies migrated; Finishing"
    Rails.logger.info message
    puts message
    true
  end

  private

  # sets a url-safe version of study name (for linking)
  def set_url_safe_name
    self.url_safe_name = self.name.downcase.gsub(/[^a-zA-Z0-9]+/, '-').chomp('-')
  end

  # used for creating symbolic links to make data downloadable
  def check_public?
    if self.public?
      if !Dir.exists?(self.data_public_path)
        FileUtils.mkdir_p(self.data_public_path)
        FileUtils.ln_sf(Dir.glob("#{self.data_store_path}/*"), self.data_public_path)
      else
        entries = Dir.entries(self.data_public_path).delete_if {|e| e.start_with?('.')}
        if entries.map {|e| File.directory?(Rails.root.join(self.data_public_path, e))}.uniq == [true] || entries.empty?
          FileUtils.ln_sf(Dir.glob("#{self.data_store_path}/*"), self.data_public_path)
        end
      end
    elsif !self.public?
      if Dir.exists?(self.data_public_path)
        FileUtils.remove_entry_secure(self.data_public_path, force: true)
      end
    end
  end

  # in case user has renamed study, validate link to data store
  # check_public? is fired after this, so symlinks will be checked next
  def check_data_links
    if self.url_safe_name != self.url_safe_name_was
      FileUtils.mv Rails.root.join('data', self.url_safe_name_was).to_s, Rails.root.join('data', self.url_safe_name).to_s
      # change url_safe_name in all study files
      self.study_files.each do |study_file|
        study_file.update(url_safe_name: self.url_safe_name)
      end
      # remove old symlink if changed
      if self.public?
        FileUtils.rm_rf(Rails.root.join('public', 'single_cell', 'data', self.url_safe_name_was))
      end
    end
  end

  # clean up any symlinks before deleting a study
  def remove_public_symlinks
    if Dir.exist?(self.data_public_path)
      FileUtils.rm_rf(self.data_public_path)
    end
  end

  def remove_data_dir
    FileUtils.rm_rf(self.data_store_path)
  end
end
