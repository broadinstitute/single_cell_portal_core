class Study
  include Mongoid::Document
  include Mongoid::Timestamps

  # associations and scopes
  belongs_to :user
  has_many :study_files, dependent: :destroy
  has_many :clusters, dependent: :destroy
  has_many :cluster_points, dependent: :destroy
  has_many :single_cells, dependent: :destroy
  has_many :expression_scores, dependent: :destroy
  has_many :precomputed_scores, dependent: :destroy
  has_many :study_shares, dependent: :destroy do
    def can_edit
      where(permission: 'Edit').map(&:email)
    end

    def can_view
      all.to_a.map(&:email)
    end
  end

  has_many :clusters do
    def parent_clusters
      where(cluster_type: 'parent').to_a.delete_if {|c| c.cluster_points.empty? }
    end

    def sub_cluster(name)
      where(parent_cluster: name).to_a.delete_if {|c| c.cluster_points.empty? }
    end
  end

  # field definitions & nested attributes
  field :name, type: String
  field :embargo, type: Date
  field :url_safe_name, type: String
  field :description, type: String
  field :public, type: Boolean, default: true

  accepts_nested_attributes_for :study_files, allow_destroy: true
  accepts_nested_attributes_for :study_shares, allow_destroy: true

  validates_uniqueness_of :name

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
  after_save      :check_public?
  before_destroy  :remove_public_symlinks

  # return all studies that are editable by a given user
  def self.editable(user)
    studies = self.where(user_id: user._id).to_a
    shares = StudyShare.where(email: user.email, permission: 'Edit').map(&:study)
    [studies + shares].flatten.uniq
  end

  # return all studies that are viewable by a given user
  def self.viewable(user)
    public = self.where(public: true).to_a
    owned = self.where(user_id: user._id, public: false).to_a
    shares = StudyShare.where(email: user.email).map(&:study)
    [public + owned + shares].flatten.uniq
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

  # helper to build a study file of the requested type
  def build_study_file(attributes)
    self.study_files.build(attributes)
  end

  # helper method to directly access cluster assignment file
  def cluster_assignment_file
    self.study_files.where(file_type:'Cluster Assignments').to_a.first
  end

  # method to parse master expression scores file for study and populate collection
  def make_expression_scores(expression_file, user=nil)
    Rails.logger.level = 4
    @count = 0
    @message = ["Parsing expression file: #{expression_file.name}", "..."]
    @last_line = ""
    start_time = Time.now

    # begin parse
    begin
      expression_file.update(parse_status: 'parsing')
      # open data file and grab header row with name of all cells, deleting 'GENE' at start
      expression_data = File.open(expression_file.upload.path)
      cells = expression_data.readline.chomp.split("\t")
      @last_line = "#{expression_file.name}, line 1: #{cells.join("\t")}"

      cells.shift
      # store study id for later to save memory
      study_id = self._id
      @records = []
      while !expression_data.eof?
        # grab single row of scores, parse out gene name at beginning
        row = expression_data.readline.chomp.split("\t")
        @last_line = "#{expression_file.name}, line #{expression_data.lineno}: #{row.join("\t")}"

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
        @records << {gene: gene_name, searchable_gene: gene_name.downcase, scores: significant_scores, study_id: study_id}
        @count += 1
        if @count % 1000 == 0
          ExpressionScore.create(@records)
          @records = []
        end
      end
      # clean up, print stats
      expression_data.close
      expression_file.update(parse_status: 'parsed')
      end_time = Time.now
      time = (end_time - start_time).divmod 60.0
      @message << "Completed!"
      @message << "ExpressionScores created: #{@count}"
      @message << "Total Time: #{time.first} minutes, #{time.last} seconds"
      unless user.nil?
        SingleCellMailer.notify_user_parse_complete(user.email, "Expression file: '#{expression_file.name}' has completed parsing", @message).deliver_now
      end
    rescue => e
      expression_file.update(parse_status: 'failed')
      puts "Study: #{self.name}, #{@last_line} ERROR: #{e.message}"
      raise StandardError, @last_line
    end
  end

  def make_cluster_points(assignment_file, cluster_file, cluster_type, user=nil)
    # turn off logging to make data load faster
    Rails.logger.level = 4
    # set up variables
    @message = ["Parsing cluster file: #{cluster_file.name}", "Using assignment file: #{assignment_file.name}", "Cluster type: #{cluster_type}", "..."]
    @cell_count = 0
    @cluster_count = 0
    @cluster_point_count = 0
    start_time = Time.now
    cluster_file.update(parse_status: 'parsing')
    @last_line = ""

    # begin parse
    begin
      # load cluster assignments
      clusters_data = File.open(assignment_file.upload.path).readlines.map(&:chomp).delete_if {|line| line.blank? }
      @all_clusters = {}
      assignment_headers = clusters_data.shift.split("\t").map(&:strip)
      @last_line = "#{assignment_file.name}, line 1: #{assignment_headers.join("\t")}"
      cell_index = assignment_headers.index('CELL_NAME')
      cluster_index = assignment_headers.index('CLUSTER')
      sub_index = assignment_headers.index('SUB-CLUSTER')
      clusters_data.each_with_index do |line, index|
        @last_line = "#{assignment_file.name}, line #{index + 2}: #{line}"

        vals = line.split("\t")
        cluster_name = vals[cluster_index]
        sub_cluster_name = vals[sub_index]
        cell_name = vals[cell_index]
        @all_clusters[cell_name] = {cluster: cluster_name, sub_cluster: sub_cluster_name}

        # create cluster and single_cell objects now to associate later as some cells/clusters have no coordinate data
        parent_cluster = Cluster.where(name: cluster_name, cluster_type: 'parent', study_id: self._id).first
        sub_cluster = Cluster.where(name: sub_cluster_name, cluster_type: 'sub_cluster', study_id: self._id).first
        if parent_cluster.blank?
          parent_cluster = self.clusters.build(name: cluster_name, cluster_type: 'parent', study_file_id: assignment_file._id)
          parent_cluster.save
          @cluster_count += 1
        end
        if sub_cluster.blank?
          sub_cluster = self.clusters.build(name: sub_cluster_name, parent_cluster: cluster_name, cluster_type: 'sub_cluster', study_file_id: assignment_file._id)
          sub_cluster.save
          @cluster_count += 1
        end
        parent_cell = SingleCell.where(name: cell_name, study_id: self._id, cluster_id: parent_cluster._id).first
        sub_cell = SingleCell.where(name: cell_name, study_id: self._id, cluster_id: sub_cluster._id).first
        if parent_cell.blank?
          parent_cell = self.single_cells.build(name: cell_name, cluster_id: parent_cluster._id, study_file_id: assignment_file._id)
          parent_cell.save
          @cell_count += 1
        end
        if sub_cell.blank?
          sub_cell = self.single_cells.build(name: cell_name, cluster_id: sub_cluster._id, study_file_id: assignment_file._id)
          sub_cell.save
          @cell_count += 1
        end
      end

      # get all lines and proper indices
      lines = File.open(cluster_file.upload.path).readlines.map(&:chomp).delete_if {|line| line.blank? }
      headers = lines.shift.split("\t")
      cell_name_index = headers.index('CELL_NAME')
      x_index = headers.index('X')
      y_index = headers.index('Y')
      lines.each_with_index do |line, index|
        @last_line = "#{cluster_file.name}, line #{index + 2}: #{line}"

        # parse each line and get values
        vals = line.split("\t")
        name = vals[cell_name_index]
        x = vals[x_index]
        y = vals[y_index]

        # load correct cluster & single_cell
        if cluster_type == 'parent'
          @cluster_name = @all_clusters[name][:cluster]
          @cluster_type = 'parent'
          @parent_cluster = nil
        else
          @cluster_name = @all_clusters[name][:sub_cluster]
          @cluster_type = 'sub_cluster'
          @parent_cluster = @all_clusters[name][:cluster]
        end

        cluster = Cluster.where(name: @cluster_name, cluster_type: @cluster_type, study_id: self._id, study_file_id: assignment_file._id).first
        cell = SingleCell.where(name: name, study_id: self._id, cluster_id: cluster._id, study_file_id: assignment_file._id).first

        unless cell.nil?
          # finally, create cluster point with association to cluster & single_cell
          cluster_point = cluster.cluster_points.build(x: x, y: y, single_cell_id: cell._id, study_file_id: cluster_file._id, study_id: self._id)
          cluster_point.save
          @cluster_point_count += 1
        end
      end
      # mark cluster file as parsed
      cluster_file.update(parse_status: 'parsed')

      # clean up
      end_time = Time.now
      time = (end_time - start_time).divmod 60.0
      @message << "Completed!"
      @message << "Single Cells created: #{@cell_count}"
      @message << "Clusters created: #{@cluster_count}"
      @message << "Cluster Points created: #{@cluster_point_count}"
      @message << "Total Time: #{time.first} minutes, #{time.last} seconds"
      unless user.nil?
        SingleCellMailer.notify_user_parse_complete(user.email, "Cluster file: '#{cluster_file.name}' has completed parsing", @message).deliver_now
      end
    rescue => e
      cluster_file.update(parse_status: 'failed')
      puts "Study: #{self.name}, #{@last_line} ERROR: #{e.message}"
      raise StandardError, @last_line
    end
  end

  # parse precomputed marker gene files and create documents to render in Morpheus
  def make_precomputed_scores(marker_file, list_name, user=nil)
    # turn off logging to make data load faster
    Rails.logger.level = 4
    @count = 0
    @message = ["Parsing marker list file: #{marker_file.name}", "..."]
    start_time = Time.now
    @last_line = ""

    # begin parse
    begin
      marker_file.update(parse_status: 'parsing')
      precomputed_score = self.precomputed_scores.build(name: list_name)
      marker_scores = File.open(marker_file.upload.path).readlines.map(&:strip).delete_if {|line| line.blank? }
      clusters = marker_scores.shift.split("\t")
      @last_line = "#{marker_file.name}, line 1: #{clusters.join("\t")}"

      clusters.shift # remove 'Gene Name' at start
      precomputed_score.clusters = clusters
      rows = []
      marker_scores.each_with_index do |line, index|
        @last_line = "#{marker_file.name}, line #{index + 2}: #{line}"
        vals = line.split("\t")
        gene = vals.shift
        row = {"#{gene}" => {}}
        clusters.each_with_index do |cluster, index|
          row[gene][cluster] = vals[index].to_f
        end
        rows << row
        @count += 1
      end
      precomputed_score.gene_scores = rows
      precomputed_score.save
      marker_file.update(parse_status: 'parsed')
      end_time = Time.now
      time = (end_time - start_time).divmod 60.0
      @message << "Completed!"
      @message << "Total scores created: #{@count}"
      @message << "Total Time: #{time.first} minutes, #{time.last} seconds"
      unless user.nil?
        SingleCellMailer.notify_user_parse_complete(user.email, "Marker gene list file: '#{marker_file.name}' has completed parsing", @message).deliver_now
      end
    rescue => e
      marker_file.update(parse_status: 'failed')
      puts "Study: #{self.name}, #{@last_line} ERROR: #{e.message}"
      raise StandardError, @last_line
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
      end
    elsif !self.public?
      if Dir.exists?(self.data_public_path)
        FileUtils.remove_entry_secure(self.data_public_path, force: true)
      end
    end
  end

  # clean up any symlinks before deleting a study
  def remove_public_symlinks
    if self.public?
      FileUtils.rm_rf(self.data_public_path)
    end
  end
end
