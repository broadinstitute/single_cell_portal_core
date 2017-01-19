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

  has_many :clusters, dependent: :destroy do
    def parent_clusters
      where(cluster_type: 'parent').to_a.delete_if {|c| c.cluster_points.empty? }
    end

    def sub_cluster(name)
      where(parent_cluster: name).to_a.delete_if {|c| c.cluster_points.empty? }
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

  # helper method to directly access cluster assignment file
  def cluster_assignment_file
    self.study_files.where(file_type:'Cluster Assignments').first
  end

  # helper method to directly access cluster assignment file
  def parent_cluster_coordinates_file
    self.study_files.where(file_type:'Cluster Coordinates', cluster_type: 'parent').first
  end

  # helper method to directly access cluster assignment file
  def expression_matrix_file
    self.study_files.where(file_type:'Expression Matrix').first
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
      if !self.cluster_ordinations_files.empty? && !self.initialized?
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
  end

  # parse single cluster coordinate & metadata file (name, x, y, z, metadata_cols* format)
  # uses cluster_group model instead of single clusters; group membership now defined by metadata
  def initialize_cluster_group(ordinations_file, cluster_name)
    # validate headers of definition file
    @validation_error = false
    begin
      d_file = File.open(ordinations_file.upload.path)
      headers = d_file.readline.split(/[\t,]/).map(&:strip)
      second_header = d_file.readline.split(/[\t,]/).map(&:strip)
      @last_line = "#{d_file.to_path}, line 1"
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
		@cluster_point_count = 0
    @cluster_metadata = []
		@records = []
    # begin parse
    begin
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
            values: []
        }
      end
      @cluster_group.save

      Rails.logger.info "Headers/Metadata loaded for cluster initialization using #{ordinations_file.upload_file_name} for cluster: #{cluster_name} in #{self.name}"
			# begin reading data
			while !cluster_data.eof?
				line = cluster_data.readline.strip
				@last_line = "#{ordinations_file.name}, line #{cluster_data.lineno}"
				vals = line.split(/[\t,]/)
				cell_name = vals[name_index]
				# create cell record, call create! to error out on validation failure
				@cell = SingleCell.create!(name: cell_name, cluster_group_id: @cluster_group._id, study_file_id: ordinations_file._id, study_id: self._id)
				# start creation of cluster_point object
				cluster_point = {
					cell_name: cell_name,
					x: vals[x_index],
					y: vals[y_index],
					single_cell_id: @cell._id,
					cluster_group_id: @cluster_group._id,
					study_file_id: ordinations_file._id,
					study_id: self._id,
					cell_annotations: {}
				}
        # add z coord if present
				if is_3d
					cluster_point[:z] = vals[z_index]
        end

        # add individual annotation entries for given cell
				@cluster_metadata.each do |metadata|
					metadata_val = vals[metadata[:index]]
          cluster_point[:cell_annotations]["#{metadata[:name]}"] = metadata[:type] == 'numeric' ? metadata_val.to_f : metadata_val

          # append to list of possible values if of type 'group'
          if metadata[:type] == 'group'
            existing_vals = cell_annotations.select {|annot| annot[:name] == metadata[:name]}.first
            metadata_idx = cell_annotations.index(existing_vals)
            unless existing_vals[:values].include?(metadata_val)
              cell_annotations[metadata_idx][:values] << metadata_val
              Rails.logger.info "Adding #{metadata_val} to #{@cluster_group.name} list of group values for #{metadata[:name]}"
              Rails.logger.info cell_annotations
            end
          end
				end

				@records << cluster_point
				@cluster_point_count += 1
				@bytes_parsed += line.length

				# create in batches to speed up execution
				if @cluster_point_count % 100 == 0
					ClusterPoint.create(@records)
					@records = []
					Rails.logger.info "Created #{@cluster_point_count} cluster points from #{ordinations_file.name} for cluster: #{cluster_name} in #{self.name}"
					ordinations_file.update(bytes_parsed: @bytes_parsed)
				end
      end
      # clean up
      ClusterPoint.create(@records)
      cluster_data.close

      # save cell_annotations to cluster_group object
      @cluster_group.update_attributes(cell_annotations: cell_annotations)

      ordinations_file.update(parse_status: 'parsed', bytes_parsed: ordinations_file.upload_file_size)
      # set initialized to true if possible
      if !self.expression_matrix_file.nil? && !self.initialized?
        self.update(initialized: true)
      end
    rescue => e
      ordinations_file.update(parse_status: 'failed')
      error_message = "#{@last_line} ERROR: #{e.message}"
      Rails.logger.info error_message
      raise StandardError, error_message
    end
  end

  # DEPRECATED, use initialize_cluster_group
  def make_clusters_and_cells(assignment_file, user=nil)
    # validate headers of assignment file & cluster file
    @validation_error = false
    begin
      a_file = File.open(assignment_file.upload.path)
      a_headers = a_file.readline.strip.split(/[\t,]/)
      @last_line = "#{assignment_file.name}, line 1"
      if a_headers.sort != %w(CELL_NAME CLUSTER SUB-CLUSTER)
        assignment_file.update(parse_status: 'failed')
        @validation_error = true
      end
      a_file.close
    rescue => e
      assignment_file.update(parse_status: 'failed')
      error_message = "Unexpected error: #{e.message}"
      Rails.logger.info @last_line + ' ' + error_message
      raise StandardError, error_message
    end

    # raise validation error if needed
    if @validation_error
      error_message = "file header validation failed: #{@last_line}; should be CELL_NAME, CLUSTER, SUB-CLUSTER"
      Rails.logger.info error_message
      raise StandardError, error_message
    end

    @message = []
    @cluster_count = 0
    @cell_count = 0
    @bytes_parsed = 0
    start_time = Time.now
    # begin parse
    begin
      Rails.logger.info "Beginning cluster/cell parse using #{assignment_file.name} for #{self.name}"
      # load cluster assignments
      clusters_data = File.open(assignment_file.upload.path)
      assignment_headers = clusters_data.readline.split(/[\t,]/).map(&:strip)
      @last_line = "#{assignment_file.name}, line 1"
      cell_index = assignment_headers.index('CELL_NAME')
      cluster_index = assignment_headers.index('CLUSTER')
      sub_index = assignment_headers.index('SUB-CLUSTER')
      Rails.logger.info "Clusters/cells loaded, starting record creation for #{self.name}"
      while !clusters_data.eof?
        line = clusters_data.readline.strip
        @last_line = "#{assignment_file.name}, line #{clusters_data.lineno}"
        vals = line.split(/[\t,]/)
        cluster_name = vals[cluster_index]
        sub_cluster_name = vals[sub_index]
        cell_name = vals[cell_index]

        # create cluster and single_cell objects now to associate later as some cells/clusters have no coordinate data
        parent_cluster = Cluster.where(name: cluster_name, cluster_type: 'parent', study_id: self._id).first
        sub_cluster = Cluster.where(name: sub_cluster_name, cluster_type: 'sub_cluster', study_id: self._id).first
        if parent_cluster.nil?
          parent_cluster = self.clusters.build(name: cluster_name, cluster_type: 'parent', study_file_id: assignment_file._id)
          parent_cluster.save
          @cluster_count += 1
        end
        if sub_cluster.nil?
          sub_cluster = self.clusters.build(name: sub_cluster_name, parent_cluster: cluster_name, cluster_type: 'sub_cluster', study_file_id: assignment_file._id)
          sub_cluster.save
          @cluster_count += 1
        end
        parent_cell = SingleCell.where(name: cell_name, study_id: self._id, cluster_id: parent_cluster._id).first
        if !parent_cell.nil?
          # duplicate cell entry
          user_error_message = "You have duplicate cell entries for #{cell_name}.  Please check your assignments file and try again."
          Rails.logger.info "Duplicate parent cell entry for #{cell_name} in study #{self.name} using assignment file #{assignment_file.name} (#{assignment_file._id})"
          raise StandardError, user_error_message
        end
        sub_cell = SingleCell.where(name: cell_name, study_id: self._id, cluster_id: sub_cluster._id).first
        if !sub_cell.nil?
          # duplicate cell entry
          user_error_message = "You have duplicate cell entries for #{cell_name}.  Please check your assignments file and try again."
          Rails.logger.info "Duplicate sub cell entry for #{cell_name} in study #{self.name} using assignment file #{assignment_file.name} (#{assignment_file._id})"
          raise StandardError, user_error_message
        end

        if parent_cell.nil?
          parent_cell = self.single_cells.build(name: cell_name, cluster_id: parent_cluster._id, study_file_id: assignment_file._id)
          parent_cell.save
          @cell_count += 1
        end
        if sub_cell.nil?
          sub_cell = self.single_cells.build(name: cell_name, cluster_id: sub_cluster._id, study_file_id: assignment_file._id)
          sub_cell.save
          @cell_count += 1
        end

        @bytes_parsed += line.length
        assignment_file.update(bytes_parsed: @bytes_parsed)
        if clusters_data.lineno > 0 && clusters_data.lineno % 100 == 0
          Rails.logger.info "Processed #{clusters_data.lineno} lines from #{assignment_file.name} for #{self.name}"
          Rails.logger.info "Created #{@cluster_count} clusters from #{assignment_file.name} for #{self.name}"
          Rails.logger.info "Created #{@cell_count} cells from #{assignment_file.name} for #{self.name}"
        end
      end
      # clean up
      assignment_file.update(parse_status: 'parsed', bytes_parsed: assignment_file.upload_file_size)
      end_time = Time.now
      time = (end_time - start_time).divmod 60.0
      @message << "#{assignment_file.name} parse completed!"
      @message << "Single Cells created: #{@cell_count}"
      @message << "Clusters created: #{@cluster_count}"
      @message << "Total Time: #{time.first} minutes, #{time.last} seconds"
      Rails.logger.info @message.join("\n")
      # set initialized to true if possible
      if !self.cluster_assignment_file.nil? && !self.parent_cluster_coordinates_file.nil? && !self.expression_matrix_file.nil? && !self.initialized?
        self.update(initialized: true)
      end
      unless user.nil?
        SingleCellMailer.notify_user_parse_complete(user.email, "Cluster file: '#{cluster_file.name}' has completed parsing", @message).deliver_now
      end
    rescue => e
      assignment_file.update(parse_status: 'failed')
      error_message = "#{@last_line} ERROR: #{e.message}"
      Rails.logger.info error_message
      raise StandardError, error_message
    end
  end

  # DEPRECATED, use initialize_cluster_group
  def make_cluster_points(assignment_file, cluster_file, cluster_type, user=nil)
    # set up variables
    @message = []
    @cell_count = 0
    @cluster_count = 0
    @cluster_point_count = 0
    @bytes_parsed = 0
    start_time = Time.now
    cluster_file.update(parse_status: 'parsing')
    @last_line = ""
    @validation_error = false

    # validate headers of cluster file
    begin
      c_file = File.open(cluster_file.upload.path)
      c_headers = c_file.readline.split(/[\t,]/).map(&:strip)
      @last_line = "#{cluster_file.name}, line 1"
      if c_headers.sort != %w(CELL_NAME X Y)
        cluster_file.update(parse_status: 'failed')
        @validation_error = true
      end
      c_file.close
    rescue => e
      cluster_file.update(parse_status: 'failed')
      error_message = "Unexpected error: #{e.message}"
      Rails.logger.info @last_line + ' ' + error_message
      raise StandardError, error_message
    end

    # raise validation error if needed
    if @validation_error
      error_message = "file header validation failed: #{@last_line}: should be CELL_NAME, X, Y"
      Rails.logger.info error_message
      raise StandardError, error_message
    end

    # begin parse
    begin
      Rails.logger.info "Beginning parsing cluster file: #{cluster_file.name} using assignment file: #{assignment_file.name}, cluster type: #{cluster_type} for #{self.name}"
      # get all lines and proper indices
      points_data = File.open(cluster_file.upload.path)
      headers = points_data.readline.split(/[\t,]/).map(&:strip)
      cell_name_index = headers.index('CELL_NAME')
      x_index = headers.index('X')
      y_index = headers.index('Y')

      @records = []
      @cell_names = []
      Rails.logger.info "Beginning cluster point record creation for #{self.name}"
      while !points_data.eof?
        line = points_data.readline.strip
        @last_line = "#{cluster_file.name}, line #{points_data.lineno}"
        # parse each line and get values
        vals = line.split(/[\t,]/)
        name = vals[cell_name_index]
        x = vals[x_index]
        y = vals[y_index]

        # load correct cluster & single_cell
        cells = SingleCell.where(name: name, study_id: self._id, study_file_id: assignment_file._id).to_a

        # raise error if cells cannot be found, likely an error happened when parsing assigments
        if cells.empty?
          user_error_message = "No cells were found matching #{name} in this study.  Please check your assignments file (#{assignment_file.name}) and try again."
          Rails.logger.info "No cells found matching: #{name} in study: #{self.name} from assignment file #{assignment_file.name} (#{assignment_file._id})"
          raise StandardError, user_error_message
        end

        if cluster_type == 'parent'
          all_clst = cells.map(&:cluster).compact
          clst = all_clst.select {|c| c.cluster_type == 'parent'}.first
          if clst.nil?
            user_error_message = "No corresponding top-level cluster was found for cell: #{name}.  Please check your assignment file (#{assignment_file.name}) and try again."
            Rails.logger.info "No parent clusters found for cell: #{name} in study: #{self.name} from assignment file #{assignment_file.name} (#{assignment_file._id}), cluster file: #{cluster_file.name} (#{cluster_file._id})"
            raise StandardError, user_error_message
          end
          @cluster_name = clst.name
          @cluster_type = 'parent'
          @parent_cluster = nil
        else
          all_clst = cells.map(&:cluster).compact
          clst = all_clst.select {|c| c.cluster_type == 'sub_cluster'}.first
          if clst.nil?
            user_error_message = "No corresponding sub-cluster was found for cell: #{name}.  Please check your assignment file (#{assignment_file.name}) and try again."
            Rails.logger.info "No sub clusters found for cell: #{name} in study: #{self.name} from assignment file #{assignment_file.name} (#{assignment_file._id}), cluster file: #{cluster_file.name} (#{cluster_file._id})"
            raise StandardError, user_error_message
          end
          @cluster_name = clst.name
          @cluster_type = 'sub_cluster'
          @parent_cluster = clst.parent_cluster
        end

        cluster = Cluster.where(name: @cluster_name, cluster_type: @cluster_type, study_id: self._id, study_file_id: assignment_file._id).first
        cell = SingleCell.where(name: name, study_id: self._id, cluster_id: cluster._id, study_file_id: assignment_file._id).first


        unless cell.nil?
          # make sure this isn't a duplicate cell first
          if @cell_names.include?(cell.name)
            user_error_message = "You have a duplicate entry for cell: #{name} in this cluster.  Please check your coordinates file and try again."
            Rails.logger.info "Duplicate cell: #{name} in coordinate file #{cluster_file.name} (#{cluster_file.id}) for study: #{self.name}"
            raise StandardError, user_error_message
          end
          # finally, create cluster point with association to cluster & single_cell
          @records << {x: x, y: y, cell_name: cell.name, single_cell_id: cell._id, cluster_id: cluster._id, study_file_id: cluster_file._id, study_id: self._id}
          @cluster_point_count += 1
          @bytes_parsed += line.length
          @cell_names << cell.name
        end
        if @cluster_point_count % 100 == 0
          ClusterPoint.create(@records)
          @records = []
          Rails.logger.info "Created #{@cluster_point_count} cluster points from #{cluster_file.name} for #{self.name}"
          cluster_file.update(bytes_parsed: @bytes_parsed)
        end
      end
      # clean up last few records
      ClusterPoint.create(@records)
      # mark cluster file as parsed
      cluster_file.update(parse_status: 'parsed', bytes_parsed: cluster_file.upload_file_size)

      # clean up
      end_time = Time.now
      time = (end_time - start_time).divmod 60.0
      @message << "#{cluster_file.name} parse completed!"
      @message << "Cluster Points created: #{@cluster_point_count}"
      @message << "Total Time: #{time.first} minutes, #{time.last} seconds"
      Rails.logger.info @message.join("\n")
      # set initialized to true if possible
      if !self.cluster_assignment_file.nil? && !self.parent_cluster_coordinates_file.nil? && !self.expression_matrix_file.nil? && !self.initialized?
        self.update(initialized: true)
      end
      unless user.nil?
        SingleCellMailer.notify_user_parse_complete(user.email, "Cluster file: '#{cluster_file.name}' has completed parsing", @message).deliver_now
      end
    rescue => e
      cluster_file.update(parse_status: 'failed')
      error_message = "#{@last_line} ERROR: #{e.message}"
      Rails.logger.info error_message
      raise StandardError, error_message
    end
  end

  # helper method to re-parse all cluster points
  # DEPRECATED
  def reparse_cluster_points
    # remove all existing cluster points
    if !self.cluster_points.empty?
      self.cluster_points.destroy_all

      # get necessary files
      @assignment_file = self.cluster_assignment_file
      @parent_cluster_file = self.parent_cluster_coordinates_file
      @sub_cluster_files = self.study_files.select {|sf| sf.cluster_type == 'sub'}

      # reset parent cluster points
      begin
        # reset parse status
        @parent_cluster_file.update(parse_status: 'unparsed')
        puts "Reparsing parent cluster points for #{self.name}"
        self.make_cluster_points(@assignment_file, @parent_cluster_file, @parent_cluster_file.cluster_type)
      rescue => e
        error_message = "Error while reparsing parent clusters for #{self.name}"
        puts error_message
        raise StandardError error_message
      end

      # reparse all sub-cluster files
      @sub_cluster_files.each do |sub_cluster_file|
        begin
          # reset parse status
          sub_cluster_file.update(parse_status: 'unparsed')
          puts "Reparsing sub clusters using #{sub_cluster_file.name} for #{self.name}"
          self.make_cluster_points(@assignment_file, sub_cluster_file, sub_cluster_file.cluster_type)
        rescue => e
          error_message = "Error while reparsing sub clusters using #{sub_cluster_file.name} for #{self.name}"
          Rails.logger.info error_message
          raise StandardError error_message
        end
      end

      # completion message
      puts "Cluster reparsing complete for #{self.name}"
    else
      puts "No cluster points for #{self.name}; Skipping"
    end
    puts "Finished!"
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
