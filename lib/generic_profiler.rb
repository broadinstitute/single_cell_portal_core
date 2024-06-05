# generic_profiler.rb
#
# helper class to profile performance of loading clusters/expression data
# will write out results to HTML files that can be loaded for detailed results
# can also be used to profile any other method, both SCP-derived or native Ruby
class GenericProfiler

  EXPRESSION_PLOT_TYPES = %w(violin heatmap).freeze
  CONSENSUS_TYPES = [nil, 'mean', 'median'].freeze
  FLAMEGRAPH_PATH = Rails.root.join('lib', 'assets', 'perl', 'flamegraph.pl').freeze
  PROFILE_BASEDIR = Rails.root.join('tmp', 'profiling')

  # generic profiling method - handles actual RubyProf.profile call and writing of reports
  # can be used to profile any method, whether both SCP-derived or native Ruby; works with both class methods & instance methods
  #
  # * *params*
  #   - +prof_object+ (Object) => object to run method from, can be a class or an instance of a class
  #   - +prof_method+ (Symbol) => method to call on +prof_object+
  #   - +report_dir+ (String) => random dirname for controlling where reports are written
  #   - +arguments+ (Array) => positional/keyword arguments to pass to +prof_method+
  #
  # * *returns*
  #   - (Array<Pathname>) => Array of filepaths to all yielded reports from :write_profiler_reports
  #
  # * *raises*
  #   - (ArgumentError) => if :arguments is not a Hash or Array
  def self.profile(prof_object, prof_method, report_dir, *arguments)
    base_filename = set_base_filename(prof_object, prof_method)
    profile_seed = SecureRandom.hex(4)
    formatted_filename = "#{profile_seed}_#{base_filename}"
    puts "Profiling #{prof_object}##{prof_method} (#{profile_seed}) with #{arguments.size} argument(s)"
    write_args_list(report_dir, profile_seed, *arguments)
    profile = RubyProf.profile { prof_object.send(prof_method, *arguments) }
    write_profiler_reports(profile, formatted_filename, report_dir)
  end

  # write out profiler reports & images
  #
  # * *params*
  #   - +profile+ (RubyProf::Profile) => profiler results
  #   - +base_filename+ (String) => basename of report files (missing extension)
  #   - +report_dir+ (String) => random dirname for controlling where reports are written
  #
  # * *yields*
  #   - (RubyProf::GraphHtmlPrinter) => html profile report
  #   - (RubyProf::FlameGraphPrinter) => flamegraph profile report (call stack)
  #   - (SVG) => FlameGraph SVG
  #
  # * *returns*
  #   - (Array<Pathname>) => Array of filepaths to all yielded reports
  def self.write_profiler_reports(profile, base_filename, report_dir)
    puts "Profiling complete, writing reports"
    reports_basepath = make_profile_dir(report_dir)
    html_filepath = Rails.root.join(reports_basepath, base_filename + '.html')
    puts "writing HTML results to #{html_filepath}"
    write_report(html_filepath, RubyProf::GraphHtmlPrinter.new(profile))
    [html_filepath]
  end

  # write a single report to specified path
  # will ensure closure to avoid issues during tests regarding file handlers & garbage collection
  #
  # * *params*
  #   - +report_path+ (String, Pathname) => path to specified report to be written
  #   - +printer+ (RubyProf::AbstractPrinter) => any RubyProf printer class instance
  #
  # * *yields*
  #   - (File) => report file of requested type at specified path
  def self.write_report(report_path, printer)
    begin
      report = File.new(report_path, 'w+')
      printer.print(report)
    rescue Errno::ENOENT => e
      # this rescue is mainly for test stability
      puts "error writing report: #{e.message}"
      report_path
    ensure
      report.try(:close)
    end
  end

  # write out text file with all arguments from profiling run, for provenance
  #
  # * *params*
  #   - +report_dir+ (String) => random dirname for controlling where reports are written
  #   - +profile_seed+ (String) => random seed corresponding to a profiling run (for matching arg lists)
  #   - +args+ (Array) => list of arguments to write
  #
  # * *yields*
  #   - (File) => text file of argument list
  def self.write_args_list(report_dir, profile_seed, *args)
    reports_basepath = make_profile_dir(report_dir)
    File.open(Rails.root.join(reports_basepath, "#{profile_seed}_arguments.txt"), 'w+') do |arguments_file|
      puts "ARGUMENTS:\n"
      args.each do |arg|
        write_single_argument(arguments_file, arg)
      end
    end
  end

  ##
  # Specialized profilers
  # pre-configured profiling methods for loading clustering & gene expression data
  ##

  # profile performance of loading clustering data from ClustersController.get_cluster_viz_data
  # will show wall time performance of all sub-method calls with complete rollups
  #
  # * *params*
  #   - +study_accession+ (String) => accession of study to use, preferably w/ >= 1M cells
  #
  # * *returns*
  #   - (Array<Pathname>) => Array of filepaths to all yielded reports
  #
  # * *raises*
  #   - (ArgumentError) => if study/cluster/annotation are not present
  def self.profile_clustering(study_accession)
    validate_cluster_args(study_accession)
    profile_dir = SecureRandom.hex(4)
    reports = []
    study = Study.find_by(accession: study_accession)
    cluster = study.default_cluster
    annotation = study.default_annotation
    subsamples = cluster.subsample_thresholds_required.reverse + [:all]
    subsamples.each do |bm_threshold|
      subsample_threshold = bm_threshold == :all ? nil : bm_threshold
      annotation_name, annotation_type, annotation_scope = annotation.split('--')
      url_params = {
        annot_name: annotation_name, annot_type: annotation_type, annot_scope: annotation_scope,
        subsample: subsample_threshold
      }
      reports += profile(
        Api::V1::Visualization::ClustersController, :get_cluster_viz_data, profile_dir, study, cluster, url_params
      )
    end
    reports
  end

  # profile performance of loading expression data from ExpressionVizService.get_global_expression_render_data
  # and ExpressionVizService.get_morpheus_text_data, depending on requested type
  # will show wall time performance of all sub-method calls with complete rollups
  #
  # * *params*
  #   - +study_accession+ (String) => accession of study to use, preferably w/ >= 1M cells
  #   - +genes+ (String) => name of gene(s) to load as comma- or space-delimited string, can be omitted to chose random genes from study
  #   - +plot_type+ (String) => plot type, either violin or heatmap, defaults to violin
  #   - +consensus+ (String) => 'collapse by' measurement: mean or median, or nil to omit consensus collapse
  #
  # * *returns*
  #   - (Array<Pathname>) => Array of filepaths to all yielded reports
  #
  # * *raises*
  #   - (ArgumentError) => if study/cluster/annotation/genes are not present
  def self.profile_expression(study_accession, genes: nil, plot_type: 'violin', consensus: nil)
    validate_cluster_args(study_accession)
    study = Study.find_by(accession: study_accession)
    validate_expression_args(study, genes, plot_type, consensus)
    reports = []
    profile_dir = SecureRandom.hex(4)
    requested_genes = genes.blank? ? study.genes.sample.name : genes
    cluster = study.default_cluster
    annotation_name, annotation_type, annotation_scope = study.default_annotation.split('--')
    annotation = AnnotationVizService.get_selected_annotation(study,
                                                              cluster: cluster,
                                                              annot_name: annotation_name,
                                                              annot_type: annotation_type,
                                                              annot_scope: annotation_scope)
    subsamples = cluster.subsample_thresholds_required.reverse + [:all]
    subsamples.each do |bm_threshold|
      subsample_threshold = bm_threshold == :all ? nil : bm_threshold
      # profile loading genes, then actually load them to pass downstream
      reports += profile(
        RequestUtils, :get_genes_from_param, profile_dir, study, requested_genes
      )
      study_genes = RequestUtils.get_genes_from_param(study, requested_genes)
      case plot_type
      when 'violin'
        reports += profile(
          ExpressionVizService, :get_global_expression_render_data, profile_dir,
          study: study, cluster: cluster, genes: study_genes, subsample: subsample_threshold,
           selected_annotation: annotation, consensus: consensus, boxpoints: 'all', current_user: study.user
        )
      when 'heatmap'
        reports += profile(
          ExpressionVizService, :get_morpheus_text_data, profile_dir, study: study, cluster: cluster,
          genes: study_genes, file_type: :gct, selected_annotation: annotation, collapse_by: nil
        )
        reports += profile(
          AnnotationVizService, :annotation_cell_values_tsv, profile_dir, study, cluster,
          annotation
        )
      end
    end
    reports
  end

  private

  # validate arguments for :profile_clustering and :profile_expression
  def self.validate_cluster_args(study_accession)
    study = Study.find_by(accession: study_accession)
    raise ArgumentError.new("\"#{study_accession}\" is not valid") if study.nil?
    cluster = study.default_cluster
    annotation = study.default_annotation
    raise ArgumentError.new("\"#{study_accession}\" cannot visualize clusters") if (cluster.nil? || annotation.nil?)
    true
  end

  # validate arguments for :profile_expression
  def self.validate_expression_args(study, genes, plot_type, consensus)
    raise ArgumentError.new("\"#{study.accession}\" has no gene expression data") if study.genes.empty?
    raise ArgumentError.new("\"#{plot_type}\" is not a valid plot type") if !EXPRESSION_PLOT_TYPES.include?(plot_type)
    raise ArgumentError.new("\"#{consensus}\" is not a valid consensus") if !CONSENSUS_TYPES.include?(consensus)
    if genes.present?
      names = extract_gene_names(genes)
      raise ArgumentError.new("\"#{genes}\" not present in #{study.accession}") if study.genes.where(:name.in => names).empty?
    end
    true
  end

  # create scratch dir for profiling results
  def self.make_profile_dir(report_dir)
    reports_basepath = Rails.root.join(PROFILE_BASEDIR, report_dir)
    FileUtils.mkdir_p(reports_basepath) unless Dir.exist?(reports_basepath)
    reports_basepath
  end

  # set the base filename for reports
  # includes object & method name, as well as formatted args list
  def self.set_base_filename(object, method_name)
    object_name = get_object_name(object)
    "#{object_name}##{method_name}"
  end

  # get a formatted "name" for set_base_filename
  # will try to use :accession first for studies, and after that will try a series of fallbacks to format object name
  def self.get_object_name(object)
    if object.respond_to?(:accession)
      object.accession
    elsif object.is_a?(Class)
      object.to_s.gsub(/\W/, '-')
    elsif object.is_a?(String)
      object.gsub(/\s/, '-')
    else
      object.class.name
    end
  end

  # split gene names on space/comma
  def self.extract_gene_names(gene_string)
    gene_string.split(/\s|,/)
  end

  def self.write_single_argument(file_handler, arg)
    if arg.is_a?(Hash)
      arg.each_pair do |key, value|
        arg_val = "#{key}: #{value.inspect}"
        puts arg_val
        file_handler.write("####\n#{arg_val}\n")
      end
    else
      arg_val = arg.inspect
      puts arg_val
      file_handler.write("####\n#{arg_val}\n")
    end
  end
end
