# handle launching differential expression ingest jobs
class DifferentialExpressionService
  extend Loggable
  # possible cell type analogs
  CELL_TYPE_MATCHER = /cell.*type/i
  # possible clustering algorithm results
  CLUSTERING_MATCHER = /(clust|seurat|leiden|louvain|snn_res)/i
  # any categorical-type labels
  CATEGORY_MATCHER = /(categor|labels)/i
  # union of all allowed annotations
  ALLOWED_ANNOTS = Regexp.union(CELL_TYPE_MATCHER, CLUSTERING_MATCHER, CATEGORY_MATCHER)
  # specific annotations to exclude from automation
  EXCLUDED_ANNOTS = /(enrichment__cell_type)/i
  # default quota for user-requested DE jobs
  DEFAULT_USER_QUOTA = 5

  # run a differential expression job for a given study on the default cluster/annotation
  #
  # * *params*
  #   - +study_accession+ (String) => Accession of study to use
  #   - +user+            (User) => Corresponding user, will default to study owner
  #   - +machine_type+     (String) => Override default VM machine type
  #   - +dry_run+         (Boolean) => Indication of whether or not this is a pre-flight check
  #
  # * *yields*
  #   - (IngestJob) => Differential expression job in PAPI
  #
  # * *returns*
  #   - (Boolean) => True if job queues successfully
  #
  # * *raises*
  #   - (ArgumentError) => if requested parameters do not validate
  def self.run_differential_expression_on_default(study_accession, user: nil, machine_type: nil, dry_run: nil)
    study = Study.find_by(accession: study_accession)
    validate_study(study)
    raise ArgumentError, "#{study.accession} has no default cluster" if study.default_cluster.blank?
    raise ArgumentError, "#{study.accession} has no default annotation" if study.default_annotation.blank?

    annotation_name, annotation_type, annotation_scope = study.default_annotation.split('--')
    raise ArgumentError, "#{study.accession} default annotation is not group-based" if annotation_type != 'group'

    annotation = { annotation_name:, annotation_scope:, machine_type:, dry_run: }
    requested_user = user || study.user
    run_differential_expression_job(study.default_cluster, study, requested_user, **annotation)
  end

  # same as default method, except runs differential expression job on all eligible annotations
  #
  # * *params*
  #   - +study_accession+ (String) => Accession of study to use
  #   - +user+            (User) => Corresponding user, will default to study owner
  #   - +dry_run+         (Boolean) => Indication of whether or not this is a pre-flight check
  #   - +skip_existing+   (Boolean) => Skip annotations that already have DE results
  #
  # * *yields*
  #   - (IngestJob) => Differential expression job in PAPI for each valid cluster/annotation combination
  #
  # * *returns*
  #   - (Integer) => Number of DE jobs yielded
  #
  # * *raises*
  #   - (ArgumentError) => if requested study cannot run any DE jobs
  def self.run_differential_expression_on_all(study_accession, user: nil, machine_type: nil, dry_run: nil,
                                              skip_existing: false)
    study = Study.find_by(accession: study_accession)
    validate_study(study)
    eligible_annotations = find_eligible_annotations(study, skip_existing:)
    raise ArgumentError, "#{study_accession} does not have any eligible annotations" if eligible_annotations.empty?

    log_message "#{study_accession} has annotations eligible for DE; validating inputs"
    requested_user = user || study.user
    job_count = 0
    skip_count = 0
    study.cluster_groups.each do |cluster_group|
      eligible_annotations.each do |annotation|
        begin
          # skip if this is a cluster-based annotation and is not available on this cluster object
          next if annotation[:annotation_scope] == 'cluster' && annotation[:cluster_group_id] != cluster_group.id

          annotation_params = annotation.deep_dup # make a copy so we don't lose the association next time we check
          annotation_params.delete(:cluster_group_id)
          annotation_params.merge!(dry_run:, machine_type:)
          annotation_identifier = [
            annotation_params[:annotation_name], 'group', annotation_params[:annotation_scope]
          ].join('--')
          job_identifier = "#{study_accession}: #{cluster_group.name} (#{annotation_identifier})"
          if annotation_params[:machine_type]
            job_identifier += "[#{machine_type}]"
          end
          log_message "Checking DE job for #{job_identifier}"
          DifferentialExpressionService.run_differential_expression_job(
            cluster_group, study, requested_user, **annotation_params
          )
          if annotation_params[:dry_run]
            log_message "==> Dry run found job #{job_identifier}"
          else
            log_message "==> DE job for #{job_identifier} successfully launched"
          end
          job_count += 1
        rescue ArgumentError => e
          log_message "  Skipping DE job for #{job_identifier} due to: #{e.message}"
          skip_count += 1
        end
      end
    end
    log_message "#{study_accession} yielded #{job_count} differential expression jobs; #{skip_count} skipped"
    job_count
  end

  # handle setting up and launching a single differential expression job
  #
  # * *params*
  #   - +cluster_group+    (ClusterGroup) => Clustering object to source name/file from
  #   - +study+            (Study) => Study to which StudyFile belongs
  #   - +user+             (User) => User initiating parse action (for email delivery)
  #   - +annotation_name+  (String) => Name of requested annotation
  #   - +annotation_scope+ (String) => Scope of requested annotation ('study' or 'cluster')
  #   - +de_type+          (String) => Type of differential expression calculation: 'rest' (one-vs-rest) or 'pairwise'
  #   - +machine_type+     (String) => Override default VM machine type
  #   - +dry_run+          (Boolean) => Indication of whether or not this is a pre-flight check
  #
  # * *yields*
  #   - (IngestJob) => Differential expression job in PAPI
  #
  # * *returns*
  #   - (Boolean) => True if job queues successfully
  #
  # * *raises*
  #   - (ArgumentError) => if requested parameters do not validate
  def self.run_differential_expression_job(cluster_group, study, user, annotation_name:, annotation_scope:,
                                           de_type: 'rest', group1: nil, group2: nil, machine_type: nil, dry_run: nil)
    validate_study(study)
    validate_annotation(cluster_group, study, annotation_name, annotation_scope, group1:, group2:)
    cluster_url = cluster_file_url(cluster_group)
    study_file = cluster_group.study_file
    metadata_url = study_file.is_viz_anndata? ?
                     RequestUtils.data_fragment_url(study_file, 'metadata') :
                     study.metadata_file.gs_url
    cluster_group_id = cluster_group.id
    # begin assembling parameters
    de_params = {
      annotation_name:,
      annotation_scope:,
      de_type:,
      group1:,
      group2:,
      annotation_file: annotation_scope == 'cluster' ? cluster_url : metadata_url,
      cluster_file: cluster_url,
      cluster_name: set_cluster_name(study, cluster_group, annotation_name, annotation_scope),
      cluster_group_id:
    }
    raw_matrix = ClusterVizService.raw_matrix_for_cluster_cells(study, cluster_group)
    de_params[:matrix_file_path] = raw_matrix.gs_url
    de_params[:matrix_file_id] = raw_matrix.id
    if raw_matrix.file_type == 'MM Coordinate Matrix'
      de_params[:matrix_file_type] = 'mtx'
      # we know bundle exists and is completed as :raw_matrix_for_cluster_cells will throw an exception if it isn't
      bundle = raw_matrix.study_file_bundle
      gene_file = bundle.bundled_file_by_type('10X Genes File')
      barcode_file = bundle.bundled_file_by_type('10X Barcodes File')
      de_params[:gene_file] = gene_file.gs_url
      de_params[:barcode_file] = barcode_file.gs_url
    elsif raw_matrix.file_type == 'AnnData'
      de_params[:matrix_file_type] = 'h5ad'
      de_params[:file_size] = raw_matrix.upload_file_size
      de_params[:raw_location] = raw_matrix.ann_data_file_info.raw_location
    else
      de_params[:matrix_file_type] = 'dense'
    end
    params_object = DifferentialExpressionParameters.new(de_params)
    params_object.machine_type = machine_type if machine_type.present? # override :machine_type if specified
    return true if dry_run # exit before submission if specified as annotation was already validated

    if params_object.valid?
      # check if there's already a job running using these parameters and exit if so
      job_params = ApplicationController.batch_api_client.format_command_line(
        study_file:, action: :differential_expression, user_metrics_uuid: user.metrics_uuid, params_object:
      )
      running = ApplicationController.batch_api_client.find_matching_jobs(
        params: job_params, job_states: BatchApiClient::RUNNING_STATES
      )
      if running.any?
        log_message "Found #{running.count} running DE jobs: #{running.map(&:name).join(', ')}"
        log_message "Matching these parameters: #{job_params.join(' ')}"
        log_message "Exiting without queuing new job"
        false
      else
        # launch DE job
        job = IngestJob.new(study:, study_file:, user:, action: :differential_expression, params_object:)
        job.delay.push_remote_and_launch_ingest
        true
      end
    else
      raise ArgumentError, "job parameters failed to validate: #{params_object.errors.full_messages.join(', ')}"
    end
  end

  # a helper method to identify newly eligible annotations and process results
  # NOTE: this will retry any annotations that are eligible and previously failed
  # also, do not use this in a migration as it is IO blocking while jobs are assembled
  #
  # * *params*
  #   - +accessions+ (Array<String>) => array of study accessions to limit backfill processing
  #
  # * *returns*
  #   - (Hash) => Hash of stats about new results, including total_jobs and results per study
  #
  # * *yields*
  #   - (IngestJob) => new DE ingest jobs
  def self.backfill_new_results(study_accessions: nil)
    accessions = study_accessions || Study.pluck(:accession)
    total_jobs = 0
    study_results = {}
    accessions.each do |accession|
      study = Study.find_by(accession:)
      next if study.nil?

      if study_has_author_de?(study)
        log_message "#{accession} has author-uploaded results, skipping"
        next
      end

      begin
        jobs = run_differential_expression_on_all(accession, skip_existing: true)
        if jobs > 0
          total_jobs += jobs
          study_results[accession] = jobs
        end
      rescue ArgumentError => e
        log_message e.message
      end
    end
    log_message "Total new backfill jobs: #{total_jobs} across #{study_results.keys.count} studies"
    study_results[:total_jobs] = total_jobs
    study_results
  end

  # find all eligible annotations for DE for a given study
  # will restrict to cell type analog annotations
  #
  # * *params*
  #   - +study+        (Study) => Associated study object
  #   - +skip_existing+   (Boolean) => Skip annotations that already have DE results
  #
  # * *returns*
  #   - (Array<Hash>) => Array of annotation objects available for DE
  def self.find_eligible_annotations(study, skip_existing: false)
    annotations = []
    metadata = study.cell_metadata.where(annotation_type: 'group').select do |meta|
      annotation_eligible?(meta.name) && meta.can_visualize?
    end
    annotations += metadata.map { |meta| { annotation_name: meta.name, annotation_scope: 'study' } }
    # special gotcha to remove 'cell_type' metadata annotation if 'cell_type__ontology_label' is present
    if annotations.detect { |annot| annot[:annotation_name] == 'cell_type__ontology_label' }.present?
      annotations.reject! { |annot| annot[:annotation_name] == 'cell_type' }
    end
    cell_annotations = []
    groups_to_process = study.cluster_groups.select { |cg| cg.cell_annotations.any? }
    groups_to_process.map do |cluster|
      cell_annots = cluster.cell_annotations.select do |annot|
        safe_annot = annot.with_indifferent_access
        safe_annot[:type] == 'group' &&
          annotation_eligible?(safe_annot[:name]) &&
          cluster.can_visualize_cell_annotation?(safe_annot)
      end
      cell_annots.each do |annot|
        annot[:cluster_group_id] = cluster.id # for checking associations later
      end
      cell_annotations += cell_annots
    end
    annotations += cell_annotations.map do |annot|
      {
        annotation_name: annot[:name],
        annotation_scope: 'cluster',
        cluster_group_id: annot[:cluster_group_id]
      }
    end
    if skip_existing
      annotations.reject { |annotation| results_exist?(study, annotation) }
    else
      annotations
    end
  end

  # match an annotation name against any potentially valid annotations for DE analysis
  #
  # * *params*
  #   - +name+ (String) => name of annotation to match against eligible types
  #
  # * *returns*
  #   - (Boolean)
  def self.annotation_eligible?(name)
    ALLOWED_ANNOTS =~ name && EXCLUDED_ANNOTS !~ name
  end

  # determine if the requested cluster/annotation has an existing result object
  # used for setting cluster name or in pairwise DE when merging in new results
  #
  # * *params*
  #   - +study+            (Study) => Study in which results exist
  #   - +cluster_group+    (ClusterGroup) => Clustering object to source name/file from
  #   - +annotation_name+  (String) => Name of requested annotation
  #   - +annotation_scope+ (String) => Scope of requested annotation ('study' or 'cluster')
  #
  # * *returns*
  #   - (DifferentialExpressionResult, nil)
  def self.find_existing_result(study, cluster_group, annotation_name, annotation_scope)
    DifferentialExpressionResult.find_by(study:, cluster_group:, annotation_name:, annotation_scope:)
  end

  # determine if a study already has DE results for an annotation, taking scope into account
  # cluster-based annotations must match to the specified cluster in the annotation object
  # for study-wide annotations, return true if any results exist, regardless of cluster as this indicates that DE
  # was already invoked on this annotation, and all valid results should already exist (barring errors)
  # missing entries can still be backfilled with :run_differential_expression_job manually
  #
  # * *params*
  #   - +study+      (Study) => study to run DE jobs in
  #   - +annotation+ (Hash) => annotation object
  #
  # * *returns*
  #   - (Boolean)
  def self.results_exist?(study, annotation)
    ids = annotation[:scope] == 'cluster' ? [annotation[:cluster_group_id]] : study.cluster_groups.pluck(:id)
    DifferentialExpressionResult.where(
      :study => study,
      :cluster_group_id.in => ids,
      :annotation_name => annotation[:annotation_name],
      :annotation_scope => annotation[:annotation_scope]
    ).exists?
  end

  # helper to set cluster_name when existing results are present
  # this prevents result file URLs breaking because the cluster has been renamed at some point
  #
  # * *params*
  #   - +study+            (Study) => Study in which results exist
  #   - +cluster_group+    (ClusterGroup) => Clustering object to source name/file from
  #   - +annotation_name+  (String) => Name of requested annotation
  #   - +annotation_scope+ (String) => Scope of requested annotation ('study' or 'cluster')
  #
  # * *returns*
  #   - (String)
  def self.set_cluster_name(study, cluster_group, annotation_name, annotation_scope)
    find_existing_result(study, cluster_group, annotation_name, annotation_scope)&.cluster_name || cluster_group.name
  end

  # determine if a study meets the requirements for differential expression:
  # 1. public
  # 2. has clustering/metadata
  # 3. has raw counts
  # 4. has group-based annotations that can be visualized
  # 5. study owner has not uploaded any of their own differential expression results
  # Individual annotations will be validated at submission time as this is more time/resource intensive
  #
  # * *params*
  #   - +study+ (Study) => study to check eligibility for differential expression jobs
  #   - +skip_existing+   (Boolean) => Skip annotations that already have DE results
  #
  # * *returns*
  #   - (Boolean)
  def self.study_eligible?(study, skip_existing: false)
    begin
      validate_study(study)
      find_eligible_annotations(study, skip_existing:).any? &&
        study.has_raw_counts_matrices? &&
        !study_has_author_de?(study)
    rescue ArgumentError
      false
    end
  end

  # validate annotation exists and can be visualized for a DE job
  #
  # * *params*
  #   - +cluster_group+    (ClusterGroup) => Clustering object to source name/file from
  #   - +study+            (Study) => Study to which StudyFile belongs
  #   - +annotation_name+  (String) => Name of requested annotation
  #   - +annotation_scope+ (String) => Scope of requested annotation ('study' or 'cluster')
  #   - +group1+           (String) => first annotation label for pairwise
  #   - +group2+           (String) => second annotation label for pairwise
  #
  # * *raises*
  #   - (ArgumentError) => if requested parameters do not validate
  def self.validate_annotation(cluster_group, study, annotation_name, annotation_scope, group1: nil, group2: nil)
    pairwise = group1.present? || group2.present?
    validate_pairwise(group1, group2) if pairwise

    result = DifferentialExpressionResult.find_by(study:, cluster_group:, annotation_name:, annotation_scope:)
    if result.present? && !pairwise
      raise ArgumentError,
            "#{annotation_name} already exists for #{study.accession}:#{cluster_group.name}, " \
            "please delete result #{result.id} before retrying"
    elsif pairwise && result.present? && result.has_pairwise_comparison?(group1, group2)
      raise ArgumentError,
            "#{group1} vs. #{group2} pairwise already exists for #{annotation_name} on " \
              "#{study.accession}:#{cluster_group.name}, you must remove that entry from #{result.id} before retrying"
    end

    can_visualize = false
    if annotation_scope == 'cluster'
      annotation = cluster_group.cell_annotations&.detect do |annot|
        annot[:name] == annotation_name && annot[:type] == 'group'
      end
      can_visualize = annotation && cluster_group.can_visualize_cell_annotation?(annotation)
    else
      annotation = study.cell_metadata.by_name_and_type(annotation_name, 'group')
      can_visualize = annotation&.can_visualize?
    end
    identifier = "#{annotation_name}--group--#{annotation_scope}"
    raise ArgumentError, "#{identifier} is not present or is numeric-based" if annotation.nil?
    raise ArgumentError, "#{identifier} cannot be visualized" unless can_visualize

    # last, validate that the requested annotation & cluster will provide a valid intersection of annotation values
    # specifically, discard any annotation/cluster combos that only result in one distinct label
    cells_by_label = ClusterVizService.cells_by_annotation_label(cluster_group, annotation_name, annotation_scope)
    if !pairwise && cells_by_label.keys.count < 2
      raise ArgumentError, "#{identifier} does not have enough labels represented in #{cluster_group.name}"
    elsif pairwise
      missing = [group1, group2] - annotation[:values]
      raise ArgumentError, "#{annotation_name} does not contain '#{missing.join(', ')}'" if missing.any?

      cell_count = {
        group1.to_s => cells_by_label[group1]&.count.to_i,
        group2.to_s => cells_by_label[group2]&.count.to_i
      }.keep_if { |_, c| c < 2 }
      if cell_count.any?
        raise ArgumentError, "#{cell_count.keys.join(', ')} does not have enough cells represented in #{identifier} " \
          "for #{cluster_group.name}"
      end
    end
  end

  # validate a given study is able to run DE job
  #
  # * *params*
  #   - +study+ (Study) => Study to validate
  #
  # * *raises*
  #   - (ArgumentError) => If requested study is not eligible for DE
  def self.validate_study(study)
    raise ArgumentError, 'Requested study does not exist' if study.nil?
    raise ArgumentError, "#{study.accession} cannot view cluster plots" unless study.can_visualize_clusters?
  end

  # ensure both group1 and group2 are provided for pairwise calculations
  #
  # * *params*
  #   - +group1+ (String) => first annotation label for pairwise
  #   - +group2+ (String) => second annotation label for pairwise
  #
  # * *raises*
  #   - (ArgumentError) => If requested study is not eligible for DE
  def self.validate_pairwise(group1, group2)
    missing = { group1:, group2: }.keep_if { |_, v| v.blank? }
    raise ArgumentError, "must provide #{missing.keys.join(', ')} for pairwise calculation" unless missing.empty?
  end

  # determine if a study has author-uploaded DE results
  # this will stop the automatic calculation of new DE results if they add more data
  #
  # * *params*
  #   - +study+ (Study) => Study to validate
  #
  # * *returns*
  #   - (Boolean)
  def self.study_has_author_de?(study)
    study.study_files.by_type('Differential Expression').any?
  end

  # construct a filename for a differential expression output file/manifest given a set of values
  # handles special case of encoding plus signs (+) as 'pos'
  #
  # * *params*
  #   - +values+ (Array<String>) => Array of values to transform into encoded name
  #
  # * *returns*
  #   - (String)
  def self.encode_filename(values)
    values.map { |val| val.gsub(/\+/, 'pos').gsub(/\W/, '_') }.join('--')
  end

  # return a GS URL for a requested ClusterGroup, depending on file type
  #
  # * *params*
  #   - +cluster_group+ (ClusterGroup) => Clustering object to source name/file from
  #
  # * *returns*
  #   - (String)
  def self.cluster_file_url(cluster_group)
    study_file = cluster_group.study_file
    if study_file.is_viz_anndata?
      data_frag = study_file.ann_data_file_info.find_fragment(data_type: :cluster, name: cluster_group.name)
      RequestUtils.data_fragment_url(study_file, 'cluster', file_type_detail: data_frag[:obsm_key_name])
    else
      study_file.gs_url
    end
  end

  # retrieve the weekly user quota value
  #
  # * *returns*
  #   - (Integer)
  def self.get_weekly_user_quota
    config = AdminConfiguration.find_by(config_type: 'Weekly User DE Quota')
    config ? config.value.to_i : DEFAULT_USER_QUOTA
  end

  # check if a user has exceeded their weekly quota
  #
  # * *params*
  #   - +user+ (User) => user requesting DE job
  #
  # * *returns*
  #   - (Boolean)
  def self.job_exceeds_quota?(user)
    user.weekly_de_quota.to_i >= get_weekly_user_quota
  end

  # increment a given user's weekly quota
  #
  # * *params*
  #   - +user+ (User) => user requesting DE job
  def self.increment_user_quota(user)
    current_quota = user.weekly_de_quota.to_i
    current_quota += 1
    user.update(weekly_de_quota: current_quota)
  end

  # reset all user-requested DE quotas on a weekly basis
  def self.reset_all_user_quotas
    User.update_all(weekly_de_quota: 0)
  end
end
