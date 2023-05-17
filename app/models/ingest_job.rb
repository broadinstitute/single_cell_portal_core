##
# IngestJob: lightweight wrapper around a PAPI ingest job with mappings to the study/file/user associated
# with this particular ingest job.  Handles polling for completion and notifying the user
##

class IngestJob
  include ActiveModel::Model

  # for getting the latest convention version
  include Api::V1::Concerns::ConventionSchemas

  # number of tries to push a file to a study bucket
  MAX_ATTEMPTS = 3

  # valid ingest actions to perform
  VALID_ACTIONS = %i[
    ingest_expression ingest_cluster ingest_cell_metadata ingest_anndata ingest_differential_expression subsample
    differential_expression render_expression_arrays
  ].freeze

  # Mappings between actions & models (for cleaning up data on re-parses)
  MODELS_BY_ACTION = {
    ingest_expression: Gene,
    ingest_cluster: ClusterGroup,
    ingest_cell_metadata: CellMetadatum,
    ingest_differential_expression: DifferentialExpressionResult,
    ingest_subsample: ClusterGroup
  }.freeze

  # non-standard job actions where data is not being read from a file to insert into MongoDB
  # these jobs usually process files and write objects back to the bucket, and as such have special pre/post-processing
  # steps that need to be accounted for
  SPECIAL_ACTIONS = %i[differential_expression render_expression_arrays image_pipeline].freeze

  # jobs that need parameters objects in order to launch correctly
  PARAMS_OBJ_REQUIRED = %i[
    differential_expression render_expression_arrays image_pipeline ingest_anndata
  ].freeze

  # Name of pipeline submission running in GCP (from [PapiClient#run_pipeline])
  attr_accessor :pipeline_name
  # Study object where file is being ingested
  attr_accessor :study
  # StudyFile being ingested
  attr_accessor :study_file
  # User performing ingest run
  attr_accessor :user
  # Action being performed by Ingest (e.g. ingest_expression, ingest_cluster)
  attr_accessor :action
  # Boolean indication of whether or not to delete old data
  attr_accessor :reparse
  # Boolean indication of whether or not to delete file from bucket on parse failure
  attr_accessor :persist_on_fail
  # Class containing extra parameters for a specific job (e.g. DifferentialExpressionParameters)
  attr_accessor :params_object

  # validations
  validates :pipeline_name, :study, :study_file, :user, :action,
            presence: true
  validates :action, inclusion: VALID_ACTIONS
  validates :params_object, presence: true, if: -> { PARAMS_OBJ_REQUIRED.include? action.to_sym }

  # Push a file to a workspace bucket in the background and then launch an ingest run and queue polling
  # Can also clear out existing data if necessary (in case of a re-parse)
  #
  # * *yields*
  #   - (Google::Apis::GenomicsV2alpha1::Operation) => Will submit an ingest job in PAPI
  #   - (IngestJob.new(attributes).poll_for_completion) => Will queue a Delayed::Job to poll for completion
  #
  # * *raises*
  #   - (RuntimeError) => If file cannot be pushed to remote bucket
  def push_remote_and_launch_ingest
    begin
      file_identifier = "#{study_file.bucket_location}:#{study_file.id}"
      rails_model = MODELS_BY_ACTION[action]
      if reparse && rails_model.present?
        Rails.logger.info "Deleting existing data for #{file_identifier}"
        rails_model.where(study_id: study.id, study_file_id: study_file.id).delete_all
        DataArray.where(study_id: study.id, study_file_id: study_file.id).delete_all
        Rails.logger.info "Data cleanup for #{file_identifier} complete, now beginning Ingest"
      end
      # first check if file is already in bucket (in case user is syncing)
      remote = ApplicationController.firecloud_client.get_workspace_file(study.bucket_id, study_file.bucket_location)
      if remote.nil?
        is_pushed = poll_for_remote
      else
        is_pushed = true # file is already in bucket
      end
      if !is_pushed
        # push has failed 3 times, so exit and report error
        log_message = "Unable to push #{file_identifier} to #{study.bucket_id}"
        Rails.logger.error log_message
        raise log_message
      else
        if can_launch_ingest?
          Rails.logger.info "Remote found for #{file_identifier}, launching Ingest job"
          submission = ApplicationController.papi_client.run_pipeline(study_file: study_file, user: user,
                                                                      action: action, params_object: params_object)
          Rails.logger.info "Ingest run initiated: #{submission.name}, queueing Ingest poller"
          IngestJob.new(pipeline_name: submission.name, study: study, study_file: study_file,
                        user: user, action: action, reparse: reparse,
                        persist_on_fail: persist_on_fail, params_object: params_object).poll_for_completion
        else
          run_at = 2.minutes.from_now
          Rails.logger.info "Remote found for #{file_identifier} but ingest gated by other parse jobs, queuing another check for #{run_at}"
          delay(run_at: run_at).push_remote_and_launch_ingest
        end
      end
    rescue => e
      Rails.logger.error "Error in launching ingest of #{file_identifier}: #{e.class.name}:#{e.message}"
      ErrorTracker.report_exception(e, user, study, study_file, { action: action})
      # notify admins of failure, and notify user that admins are looking into the issue
      SingleCellMailer.notify_admin_parse_launch_fail(study, study_file, user, action, e).deliver_now
      user_message = "<p>An error has occurred when attempting to launch the parse job associated with #{study_file.upload_file_name}.  "
      user_message += 'Support staff has been notified and are investigating the issue.  '
      user_message += 'If you require immediate assistance, please contact scp-support@broadinstitute.zendesk.com.</p>'
      unless special_action?
        SingleCellMailer.user_notification(user, "Unable to parse #{study_file.upload_file_name}", user_message).deliver_now
      end
    end
  end

  # helper method to push & poll for remote file
  #
  # * *returns*
  #   - (Boolean) => Indication of whether or not file has reached bucket
  def poll_for_remote
    attempts = 1
    is_pushed = false
    file_identifier = "#{study_file.bucket_location}:#{study_file.id}"
    while !is_pushed && attempts <= MAX_ATTEMPTS
      Rails.logger.info "Preparing to push #{file_identifier} to #{study.bucket_id}"
      study.send_to_firecloud(study_file)
      Rails.logger.info "Polling for upload of #{file_identifier}, attempt #{attempts}"
      remote = ApplicationController.firecloud_client.get_workspace_file(study.bucket_id, study_file.bucket_location)
      if remote.present?
        is_pushed = true
      else
        interval = 30 * attempts
        sleep interval
        attempts += 1
      end
    end
    is_pushed
  end

  # Determine if a file is ready to be ingested.  This mainly validates that other concurrent parses for the same study
  # will not interfere with validation for this current run
  #
  # * *returns*
  #   - (Boolean) => T/F if file can launch PAPI ingest job
  def can_launch_ingest?
    case study_file.file_type
    when /Matrix/
      # expression matrices currently cannot be ingested in parallel due to constraints around validating cell names
      # this block ensures that all other matrices have all cell names ingested and at least one gene entry, which
      # ensures the matrix has validated
      other_matrix_files = study.expression_matrices.where(:id.ne => study_file.id)
      # only check other matrix files of the same type, as this is what will be checked when validating
      similar_matrix_files = other_matrix_files.select {|matrix| matrix.is_raw_counts_file? == study_file.is_raw_counts_file?}
      similar_matrix_files.each do |matrix_file|
        if matrix_file.parsing?
          matrix_cells = study.expression_matrix_cells(matrix_file)
          matrix_genes = Gene.where(study_id: study.id, study_file_id: matrix_file.id)
          if !matrix_cells || matrix_genes.empty?
            # return false if matrix hasn't validated, unless the other matrix was uploaded after this file
            # this is to prevent multiple matrix files queueing up and blocking each other from initiating PAPI jobs
            # also, a timeout 24 hours is added to prevent all matrix files from queueing infinitely if one
            # fails to launch an ingest job for some reason
            if matrix_file.created_at < study_file.created_at && matrix_file.created_at > 24.hours.ago
              return false
            end
          end
        end
      end
      true
    else
      # no other file types currently are gated for launching ingest
      true
    end
  end

  # Patch for using with Delayed::Job.  Returns true to mimic an ActiveRecord instance
  #
  # * *returns*
  #   - True::TrueClass
  def persisted?
    true
  end

  # Get all instance variables associated with job
  #
  # * *returns*
  #   - (Hash) => Hash of all instance variables
  def attributes
    {
      study: study,
      study_file: study_file,
      user: user,
      action: action,
      reparse: reparse,
      persist_on_fail: persist_on_fail,
      params_object: params_object&.attributes
    }
  end

  # Return an updated reference to this ingest run in PAPI
  #
  # * *returns*
  #   - (Google::Apis::GenomicsV2alpha1::Operation)
  def get_ingest_run
    ApplicationController.papi_client.get_pipeline(name: pipeline_name)
  end

  # Determine if this ingest run has done by checking current status
  #
  # * *returns*
  #   - (Boolean) => Indication of whether or not job has completed
  def done?
    get_ingest_run.done?
  end

  # Get all errors for ingest job
  #
  # * *returns*
  #   - (Google::Apis::GenomicsV2alpha1::Status)
  def error
    get_ingest_run.error
  end

  # Determine if a job failed by checking for errors
  #
  # * *returns*
  #   - (Boolean) => Indication of whether or not job failed via an unrecoverable error
  def failed?
    error.present?
  end

  # Get a status label for current state of job
  #
  # * *returns*
  #   - (String) => Status label
  def current_status
    if done?
      failed? ? 'Error' : 'Completed'
    else
      'Running'
    end
  end

  # Get the PAPI job metadata
  #
  # * *returns*
  #   - (Hash) => Metadata of PAPI job, including events, environment, labels, etc.
  def metadata
    get_ingest_run.metadata
  end

  # Get all the events for a given ingest job in chronological order
  #
  # * *returns*
  #   - (Array<Google::Apis::GenomicsV2alpha1::Event>) => Array of pipeline events, sorted by timestamp
  def events
    metadata['events'].sort_by! {|event| event['timestamp'] }
  end

  # Get all messages from all events
  #
  # * *returns*
  #   - (Array<String>) => Array of all messages in chronological order
  def event_messages
    events.map {|event| event['description']}
  end

  # Get the exit code for the pipeline, if present
  #
  # * *returns*
  #   - (Integer or Nil::NilClass) => integer status code or nil (if still running)
  def exit_code
    return nil unless done?

    events.each do |event|
      status = event.dig('details', 'exitStatus')
      return status.to_i if status
    end
    nil # catch-all
  end



  # Reconstruct the command line from the pipeline actions
  #
  # * *returns*
  #   - (String) => Deserialized command line
  def command_line
    command_line = ""
    metadata['pipeline']['actions'].each do |action|
      command_line += action['commands'].join(' ') + "\n"
    end
    command_line.chomp("\n")
  end

  # Get the first & last event timestamps to compute runtime
  #
  # * *returns*
  #   - (Array<DateTime>) => Array of initial and terminal timestamps from PAPI events
  def get_runtime_timestamps
    all_events = events.to_a
    start_time = DateTime.parse(all_events.first['timestamp'])
    completion_time = DateTime.parse(all_events.last['timestamp'])
    [start_time, completion_time]
  end

  # Get the total runtime of parsing from event timestamps
  #
  # * *returns*
  #   - (String) => Text representation of total elapsed time
  def get_total_runtime
    TimeDifference.between(*get_runtime_timestamps).humanize
  end

  # Get the total runtime of parsing from event timestamps, in milliseconds
  #
  # * *returns*
  #   - (Integer) => Total elapsed time in milliseconds
  def get_total_runtime_ms
    (TimeDifference.between(*get_runtime_timestamps).in_seconds * 1000).to_i
  end

  # Launch a background polling process.  Will check for completion, and if the pipeline has not completed
  # running, it will enqueue a new poller and exit to free up resources.  Defaults to checking every minute.
  # Job does not return anything, but will handle success/failure accordingly.
  #
  # * *params*
  #   - +run_at+ (DateTime) => Time at which to run new polling check
  def poll_for_completion(run_at: 1.minute.from_now)
    if done? && !failed?
      Rails.logger.info "IngestJob poller: #{pipeline_name} is done!"
      Rails.logger.info "IngestJob poller: #{pipeline_name} status: #{current_status}"
      unless special_action?
        study_file.update(parse_status: 'parsed')
        study_file.bundled_files.each { |sf| sf.update(parse_status: 'parsed') }
      end
      study.reload # refresh cached instance of study
      study_file.reload # refresh cached instance of study_file
      set_study_state_after_ingest
      study_file.invalidate_cache_by_file_type # clear visualization caches for file
      log_to_mixpanel
      subject = "#{study_file.file_type} file: '#{study_file.upload_file_name}' has completed parsing"
      message = generate_success_email_array
      if special_action?
        # don't email users for 'special actions' like DE or image pipeline, instead notify admins
        qa_config = AdminConfiguration.find_by(config_type: 'QA Dev Email')
        email = qa_config.present? ? qa_config.value : User.find_by(admin: true)&.email
        SingleCellMailer.notify_user_parse_complete(email, subject, message, study).deliver_now unless email.blank?
      else
        SingleCellMailer.notify_user_parse_complete(user.email, subject, message, study).deliver_now
      end
    elsif done? && failed?
      Rails.logger.error "IngestJob poller: #{pipeline_name} has failed."
      # log errors to application log for inspection
      log_error_messages
      log_to_mixpanel # log before queuing file for deletion to preserve properties
      # don't delete files or notify users if this is a 'special action', like DE or image pipeline jobs
      subject = "Error: #{study_file.file_type} file: '#{study_file.upload_file_name}' parse has failed"
      unless special_action?
        create_study_file_copy
        study_file.update(parse_status: 'failed')
        DeleteQueueJob.new(study_file).delay.perform
        unless persist_on_fail
          ApplicationController.firecloud_client.delete_workspace_file(study.bucket_id, study_file.bucket_location)
          study_file.bundled_files.each do |bundled_file|
            ApplicationController.firecloud_client.delete_workspace_file(study.bucket_id, bundled_file.bucket_location)
          end
        end
        user_email_content = generate_error_email_body
        SingleCellMailer.notify_user_parse_fail(user.email, subject, user_email_content, study).deliver_now
      end
      admin_email_content = generate_error_email_body(email_type: :dev)
      SingleCellMailer.notify_admin_parse_fail(user.email, subject, admin_email_content).deliver_now
    else
      Rails.logger.info "IngestJob poller: #{pipeline_name} is not done; queuing check for #{run_at}"
      delay(run_at: run_at).poll_for_completion
    end
  end

  # TODO (SCP-4709, SCP-4710) Processed and Raw expression files

  # Set study state depending on what kind of file was just ingested
  # Does not return anything, but will set state and launch other jobs as needed
  #
  # * *yields*
  #   - Study#set_cell_count, :set_study_default_options, Study#set_gene_count, and :set_study_initialized
  def set_study_state_after_ingest
    case action
    when :ingest_cell_metadata
      study.set_cell_count
      set_study_default_options
      launch_subsample_jobs unless study_file.is_anndata?
      # update search facets if convention data
      if study_file.use_metadata_convention
        SearchFacet.delay.update_all_facet_filters
      end
      launch_differential_expression_jobs unless study_file.is_anndata?
      set_anndata_file_info if study_file.is_anndata?
    when :ingest_expression
      study.delay.set_gene_count
      launch_differential_expression_jobs
    when :ingest_cluster
      set_cluster_point_count
      set_study_default_options
      launch_subsample_jobs unless study_file.is_anndata?
      launch_differential_expression_jobs unless study_file.is_anndata?
      set_anndata_file_info if study_file.is_anndata?
    when :ingest_subsample
      set_subsampling_flags
    when :differential_expression
      create_differential_expression_results
    when :ingest_differential_expression
      load_differential_expression_manifest
    when :render_expression_arrays
      launch_image_pipeline_job
    when :image_pipeline
      set_has_image_cache
    when :ingest_anndata
      launch_anndata_subparse_jobs
      set_anndata_file_info
    end
    set_study_initialized
  end

  # Set the default options for a study after ingesting Clusters/Cell Metadata
  #
  # * *yields*
  #   - Sets study default options for clusters/annotations
  def set_study_default_options
    case study_file.file_type
    when 'Metadata'
      set_default_annotation
    when 'Cluster'
      set_default_cluster
      set_default_annotation
    when 'AnnData'
      set_default_cluster
      set_default_annotation
    end
    Rails.logger.info "Setting default options in #{study.name}: #{study.default_options}"
    study.save
    # warm all default caches for this study
    ClusterCacheService.delay(queue: :cache).cache_study_defaults(study)
  end

  # get the name of an associate ClusterGroup, if one was generated from this job
  def cluster_name_by_file_type
    case study_file.file_type
    when 'Cluster'
      study_file.name
    when 'AnnData'
      params_object.name
    else
      nil
    end
  end

  # set the default annotation for the study, if not already set
  def set_default_annotation
    return if study.default_options[:annotation].present?

    cell_metadatum = study.cell_metadata.keep_if(&:can_visualize?).first || study.cell_metadata.first
    cluster = study.cluster_groups.first
    if cluster.present?
      cell_annotation = cluster.cell_annotations.select { |annot| cluster.can_visualize_cell_annotation?(annot) }
                               .first || cluster.cell_annotations.first
    else
      cell_annotation = nil
    end
    annotation_object = cell_metadatum || cell_annotation
    return if annotation_object.nil?

    if annotation_object.is_a?(CellMetadatum)
      study.default_options[:annotation] = annotation_object.annotation_select_value
      is_numeric = annotation_object.annotation_type == 'numeric'
    elsif annotation_object.is_a?(Hash) && cluster.present?
      study.default_options[:annotation] = cluster.annotation_select_value(annotation_object)
      is_numeric = annotation_object[:type] == 'numeric'
    end
    study.default_options[:color_profile] = 'Reds' if is_numeric
  end

  # set the default cluster for the study, if not already set
  def set_default_cluster
    if study.default_options[:cluster].nil?
      cluster = study.cluster_groups.by_name(cluster_name_by_file_type)
      study.default_options[:cluster] = cluster.name if cluster.present?
    end
  end

  # set the point count on a cluster group after successful ingest
  #
  # * *yields*
  #   - sets the :points attribute on a ClusterGroup
  def set_cluster_point_count
    cluster_group = ClusterGroup.find_by(study_id: study.id, study_file_id: study_file.id, name: cluster_name_by_file_type)
    if cluster_group.present?
      cluster_group.set_point_count!
      Rails.logger.info "Point count on #{cluster_group.name}:#{cluster_group.id} set to #{cluster_group.points}"
    end
  end

  # Set the study "initialized" attribute if all main models are populated
  #
  # * *yields*
  #   - Sets study initialized to True if needed
  def set_study_initialized
    if study.cluster_groups.any? && study.genes.any? && study.cell_metadata.any? && !study.initialized?
      study.update(initialized: true)
    end
  end

  # determine if subsampling needs to be run based on file ingested and current study state
  #
  # * *yields*
  #   - (IngestJob) => new ingest job for subsampling
  def launch_subsample_jobs
    case study_file.file_type
    when 'Cluster'
      # only subsample if ingest_cluster was just run, new cluster is > 1K points, and a metadata file is parsed
      cluster_ingested = action.to_sym == :ingest_cluster
      cluster = ClusterGroup.find_by(study_id: study.id, study_file_id: study_file.id)
      metadata_parsed = study.metadata_file.present? && study.metadata_file.parsed?
      if cluster_ingested && metadata_parsed && cluster.can_subsample? && !cluster.is_subsampling?
        # immediately set cluster.is_subsampling = true to gate race condition if metadata file just finished parsing
        cluster.update(is_subsampling: true)
        file_identifier = "#{study_file.bucket_location}:#{study_file.id}"
        Rails.logger.info "Launching subsampling ingest run for #{file_identifier} after #{action}"
        submission = ApplicationController.papi_client.run_pipeline(study_file: study_file, user: user,
                                                                    action: :ingest_subsample)
        Rails.logger.info "Subsampling run initiated: #{submission.name}, queueing Ingest poller"
        IngestJob.new(pipeline_name: submission.name, study: study, study_file: study_file,
                      user: user, action: :ingest_subsample, reparse: false,
                      persist_on_fail: persist_on_fail).poll_for_completion
      end
    when 'Metadata'
      # subsample all cluster files that have already finished parsing.  any in-process cluster parses, or new submissions
      # will be handled by the above case.  Again, only subsample for completed clusters > 1K points
      metadata_identifier = "#{study_file.bucket_location}:#{study_file.id}"
      study.study_files.where(file_type: 'Cluster', parse_status: 'parsed').each do |cluster_file|
        cluster = ClusterGroup.find_by(study_id: study.id, study_file_id: cluster_file.id)
        if cluster.can_subsample? && !cluster.is_subsampling?
          # set cluster.is_subsampling = true to avoid future race conditions
          cluster.update(is_subsampling: true)
          file_identifier = "#{cluster_file.bucket_location}:#{cluster_file.id}"
          Rails.logger.info "Launching subsampling ingest run for #{file_identifier} after #{action} of #{metadata_identifier}"
          submission = ApplicationController.papi_client.run_pipeline(study_file: cluster_file, user: user,
                                                                      action: :ingest_subsample)
          Rails.logger.info "Subsampling run initiated: #{submission.name}, queueing Ingest poller"
          IngestJob.new(pipeline_name: submission.name, study: study, study_file: cluster_file,
                        user: user, action: :ingest_subsample, reparse: reparse,
                        persist_on_fail: persist_on_fail).poll_for_completion
        end
      end
    end
  end

  # Set correct subsampling flags on a cluster after job completion
  def set_subsampling_flags
    cluster_group = ClusterGroup.find_by(study_id: study.id, study_file_id: study_file.id, name: cluster_name_by_file_type)
    if cluster_group.is_subsampling? && cluster_group.find_subsampled_data_arrays.any?
      Rails.logger.info "Setting subsampled flags for #{study_file.upload_file_name}:#{study_file.id} (#{cluster_group.name}) for visualization"
      cluster_group.update(subsampled: true, is_subsampling: false)
    end
  end

  # determine if differential expression should be run for study, and submit available jobs (skipping existing results)
  def launch_differential_expression_jobs
    if DifferentialExpressionService.study_eligible?(study, skip_existing: true)
      Rails.logger.info "#{study.accession} is eligible for differential expression, launching available jobs"
      DifferentialExpressionService.run_differential_expression_on_all(study.accession, skip_existing: true)
    end
  end

  # set corresponding differential expression flags on associated annotation
  def create_differential_expression_results
    annotation_identifier = "#{params_object.annotation_name}--group--#{params_object.annotation_scope}"
    Rails.logger.info "Creating differential expression result object for annotation: #{annotation_identifier}"
    cluster = ClusterGroup.find_by(study_id: study.id, study_file_id: study_file.id)
    matrix_url = params_object.matrix_file_path
    matrix_filename = matrix_url.split("gs://#{study.bucket_id}/").last
    matrix_file = StudyFile.where(study: study, 'expression_file_info.is_raw_counts' => true).any_of(
      { upload_file_name: matrix_filename }, { remote_location: matrix_filename }
    ).first
    de_result = DifferentialExpressionResult.new(
      study: study, cluster_group: cluster, cluster_name: cluster.name,
      annotation_name: params_object.annotation_name, annotation_scope: params_object.annotation_scope,
      matrix_file_id: matrix_file.id
    )
    de_result.save
  end

  # read the DE manifest file generated during ingest_differential_expression to create DifferentialExpressionResult
  # entry for given annotation/cluster, and populate any one-vs-rest or pairwise_comparisons
  def load_differential_expression_manifest
    de_info = study_file.differential_expression_file_info
    annotation_identifier = "#{de_info.annotation_name}--group--#{de_info.annotation_scope}"
    Rails.logger.info "Creating differential expression result object for annotation: #{annotation_identifier} from " \
                      "user-uploaded file #{study_file.upload_file_name}"
    # TODO: SCP-5096, once SCP-4999 & SCP-5087 are completed
  end

  # launch an image pipeline job once :render_expression_arrays completes
  def launch_image_pipeline_job
    Rails.logger.info "Launching image_pipeline job in #{study.accession} for cluster file: #{study_file.name}"
    ImagePipelineService.run_image_pipeline_job(study, study_file, user:, data_cache_perftime: get_total_runtime_ms)
  end

  # set flags to denote when a cluster has image data
  def set_has_image_cache
    Rails.logger.info "Setting image_pipeline flags in #{study.accession} for cluster: #{study_file.name}"
    cluster_group = ClusterGroup.find_by(study_id: study.id, study_file_id: study_file.id)
    cluster_group.update(has_image_cache: true) if cluster_group.present?
  end

  # set appropriate flags for AnnDataFileInfo entries
  def set_anndata_file_info
    study_file.build_ann_data_file_info if study_file.ann_data_file_info.nil?

    study_file.ann_data_file_info.has_clusters = ClusterGroup.where(study:, study_file:).exists?
    study_file.ann_data_file_info.has_metadata = CellMetadatum.where(study:, study_file:).exists?
    study_file.ann_data_file_info.has_expression = Gene.where(study:, study_file:).exists?
    study_file.save
  end

  # launch appropriate downstream jobs once an AnnData file successfully extracts "fragment" files
  def launch_anndata_subparse_jobs
    # reference AnnData uploads don't have extract parameter so exit immediately
    return nil if params_object.extract.blank?

    params_object.extract.each do |extract|
      case extract
      when 'cluster'
        params_object.obsm_keys.each do |fragment|
          Rails.logger.info "launching AnnData #{fragment} cluster extraction for #{study_file.upload_file_name}"
          matcher = { data_type: :cluster, obsm_key_name: fragment }
          cluster_data_fragment = study_file.ann_data_file_info.find_fragment(**matcher)
          name = cluster_data_fragment&.[](:name) || fragment # fallback if we can't find data_fragment
          cluster_gs_url = params_object.fragment_file_url(study.bucket_id, 'cluster', study_file.id, fragment)
          domain_ranges = study_file.ann_data_file_info.get_cluster_domain_ranges(name).to_json
          cluster_params = AnnDataIngestParameters.new(
            ingest_cluster: true, name:, cluster_file: cluster_gs_url, domain_ranges:, ingest_anndata: false,
            extract: nil, obsm_keys: nil
          )
          job = IngestJob.new(study:, study_file:, user:, action: :ingest_cluster, params_object: cluster_params)
          job.delay.push_remote_and_launch_ingest
        end
      when 'metadata'
        Rails.logger.info "launching AnnData metadata extraction for #{study_file.upload_file_name}"
        metadata_gs_url = params_object.fragment_file_url(study.bucket_id, 'metadata', study_file.id)
        metadata_params = AnnDataIngestParameters.new(
          ingest_cell_metadata: true, cell_metadata_file: metadata_gs_url,
          ingest_anndata: false, extract: nil, obsm_keys: nil, study_accession: study.accession
        )
        job = IngestJob.new(study:, study_file:, user:, action: :ingest_cell_metadata, params_object: metadata_params)
        job.delay.push_remote_and_launch_ingest
      else
        # processed_expression data is parsed during the initial extract phase, so nothing is required here
        # logging is for debugging purposes only
        Rails.logger.info "skipping extraction of #{extract} for #{study_file.upload_file_name}"
      end
    end
  end

  # set corresponding is_differential_expression_enabled flags on annotations

  # store a copy of a study file when an ingest job fails in the parse_logs/:id directory for QA purposes
  #
  # * *returns*
  #   - (Boolean) => True/False on success of file copy action
  def create_study_file_copy
    begin
      ApplicationController.firecloud_client.execute_gcloud_method(:copy_workspace_file, 0,
                                                                   study.bucket_id,
                                                                   study_file.bucket_location,
                                                                   study_file.parse_fail_bucket_location)
      if study_file.is_bundled? && study_file.is_bundle_parent?
        study_file.bundled_files.each do |file|
          # put in same directory as parent file for ease of debugging
          bundled_file_location = "parse_logs/#{study_file.id}/#{file.upload_file_name}"
          ApplicationController.firecloud_client.execute_gcloud_method(:copy_workspace_file, 0,
                                                                       study.bucket_id,
                                                                       file.bucket_location,
                                                                       bundled_file_location)
        end
      end
      true
    rescue => e
      ErrorTracker.report_exception(e, user, study_file, { action: :create_study_file_copy})
      false
    end
  end

  # path to dev error file in study bucket, containing debug messages and stack traces
  #
  # * *returns*
  #   - (String) => String representation of path to detailed log file
  def dev_error_filepath
    "parse_logs/#{study_file.id}/log.txt"
  end

  # path to user-level error log file in study bucket
  #
  # * *returns*
  #   - (String) => String representation of path to log file
  def user_error_filepath
    "parse_logs/#{study_file.id}/user_log.txt"
  end

  # in case of an error, retrieve the contents of the warning or error file to email to the user
  # deletes the file immediately after being read
  #
  # * *params*
  #   - +filepath+ (String) => relative path of file to read in bucket
  #   - +delete_on_read+ (Boolean) => T/F to remove logfile from bucket after reading, defaults to true
  #   - +range+ (Range) => Byte range to read from file
  #
  # * *returns*
  #   - (String) => Contents of file
  def read_parse_logfile(filepath, delete_on_read: true, range: nil)
    if ApplicationController.firecloud_client.workspace_file_exists?(study.bucket_id, filepath)
      file_contents = ApplicationController.firecloud_client.execute_gcloud_method(:read_workspace_file, 0, study.bucket_id, filepath)
      ApplicationController.firecloud_client.execute_gcloud_method(:delete_workspace_file, 0, study.bucket_id, filepath) if delete_on_read
      # read file range manually since GCS download requests don't honor range parameter apparently
      range.present? ? file_contents.read[range] : file_contents.read
    end
  end

  # gather statistics about this run to report to Mixpanel
  #
  # * *returns*
  #   - (Hash) => Hash of job statistics to use with IngestJob#log_to_mixpanel
  def get_job_analytics
    file_type = study_file.file_type

    trigger = study_file.remote_location.present? ?  'sync' : 'upload'

    # retrieve pipeline metadata for VM information
    vm_info = metadata.dig('pipeline', 'resources', 'virtualMachine')

    job_perftime = get_total_runtime_ms
    # Event properties to log to Mixpanel.
    # Mixpanel uses camelCase for props; snake_case would degrade Mixpanel UX.
    job_props = {
      perfTime: job_perftime, # Latency in milliseconds
      fileName: study_file.name,
      fileType: file_type,
      fileSize: study_file.upload_file_size,
      action: action,
      studyAccession: study.accession,
      trigger: trigger,
      jobStatus: failed? ? 'failed' : 'success',
      machineType: vm_info['machineType'],
      bootDiskSizeGb: vm_info['bootDiskSizeGb'],
      exitStatus: exit_code # integer exit code from PAPI, e.g. `137` for out of memory (OOM)
    }

    case action
    when :ingest_expression
      # since genes are not ingested for raw count matrices, report number of cells ingested
      cells = study.expression_matrix_cells(study_file)
      cell_count = cells.present? ? cells.count : 0
      job_props.merge!({ numCells: cell_count, is_raw_counts: study_file.is_raw_counts_file? })
      if !study_file.is_raw_counts_file?
        genes = Gene.where(study_id: study.id, study_file_id: study_file.id).count
        job_props.merge!({:numGenes => genes})
      end
    when :ingest_cell_metadata
      use_metadata_convention = study_file.use_metadata_convention
      job_props.merge!({useMetadataConvention: use_metadata_convention})
      if use_metadata_convention
        project_name = 'alexandria_convention' # hard-coded is fine for now, consider implications if we get more projects
        current_schema_version = get_latest_schema_version(project_name)
        job_props.merge!(
          {
            metadataConvention: project_name,
            schemaVersion: current_schema_version
          }
        )
      end
    when :ingest_cluster, :ingest_subsample
      cluster = ClusterGroup.find_by(study_id: study.id, study_file_id: study_file.id, name: cluster_name_by_file_type)
      job_props.merge!({metadataFilePresent: study.metadata_file.present?})
      # must make sure cluster is present, as parse failures may result in no data having been stored
      if cluster.present?
        cluster_type = cluster.cluster_type
        cluster_points = cluster.points
        can_subsample = cluster.can_subsample?
        job_props.merge!(
          {
            clusterType: cluster_type,
            numClusterPoints: cluster_points,
            canSubsample: can_subsample
          }
        )
      end
    when :differential_expression
      cluster = ClusterGroup.find_by(study_id: study.id, study_file_id: study_file.id)
      annotation_params = {
        cluster: cluster,
        annot_name: params_object.annotation_name,
        annot_type: 'group',
        annot_scope: params_object.annotation_scope
      }
      annotation = AnnotationVizService.get_selected_annotation(study, **annotation_params)
      job_props.merge!(
        {
          numCells: cluster&.points,
          numAnnotationValues: annotation[:values]&.size
        }
      )
    when :image_pipeline
      data_cache_perftime =  params_object.data_cache_perftime
      job_props.merge!(
        {
          'perfTime:dataCache' => data_cache_perftime,
          'perfTime:full' => data_cache_perftime + job_perftime
        }
      )
    when :ingest_anndata
      # AnnData file analytics TODO
    end
    job_props.with_indifferent_access
  end

  # logs analytics to Mixpanel
  #
  # * *yields*
  #  - MetricsService.log => reports output of IngestJob#get_job_analytics to Mixpanel via Bard
  def log_to_mixpanel
    mixpanel_log_props = get_job_analytics
    # log job properties to Mixpanel
    MetricsService.log(mixpanel_event_name, mixpanel_log_props, user)
  end

  # set a mixpanel event name based on action
  # will either be 'ingest', or '{special-action-name}-ingest'
  def mixpanel_event_name
    special_action? ? "#{action.to_s.gsub(/_/, '-')}-ingest" : 'ingest'
  end

  # generates parse completion email body
  #
  # * *returns*
  #   - (Array) => List of message strings to print in a completion email
  def generate_success_email_array
    message = ["Total parse time: #{get_total_runtime}"]
    case action
    when :ingest_expression
      # since genes are not ingested for raw count matrices, report number of cells ingested
      if study_file.is_raw_counts_file?
        cells = study.expression_matrix_cells(study_file).count
        message << "Cells ingested: #{cells}"
      else
        genes = Gene.where(study_id: study.id, study_file_id: study_file.id).count
        message << "Gene-level entries created: #{genes}"
      end
    when :ingest_cell_metadata
      use_metadata_convention = study_file.use_metadata_convention
      if use_metadata_convention
        project_name = 'alexandria_convention' # hard-coded is fine for now, consider implications if we get more projects
        current_schema_version = get_latest_schema_version(project_name)
        schema_url = 'https://singlecell.zendesk.com/hc/en-us/articles/360061006411-Metadata-Convention'
        message << "This metadata file was validated against the latest <a href='#{schema_url}'>Metadata Convention</a>"
        message << "Convention version: <strong>#{project_name}/#{current_schema_version}</strong>"
        ingest_image_attributes = AdminConfiguration.get_ingest_docker_image_attributes
        message << "Ingest Pipeline Docker image version: #{ingest_image_attributes[:tag]}"
        message << 'Group-type metadata columns with more than 200 unique values are not made available for visualization.'
      end
      cell_metadata = CellMetadatum.where(study_id: study.id, study_file_id: study_file.id)
      message << "Entries created:"
      cell_metadata.each do |metadata|
        unless metadata.nil?
          message << get_annotation_message(annotation_source: metadata)
        end
      end
    when :ingest_cluster
      cluster = ClusterGroup.find_by(study_id: study.id, study_file_id: study_file.id)
      cluster_type = cluster.cluster_type
      message << "Cluster created: #{cluster.name}, type: #{cluster_type}"
      if cluster.cell_annotations.any?
        message << "Annotations:"
        cluster.cell_annotations.each do |annot|
          message << get_annotation_message(annotation_source: cluster, cell_annotation: annot)
        end
      end
      cluster_points = cluster.points
      message << "Total points in cluster: #{cluster_points}"

      can_subsample = cluster.can_subsample?
      metadata_file_present = study.metadata_file.present?

      # notify user that subsampling is about to run and inform them they can't delete cluster/metadata files
      if can_subsample && metadata_file_present
        message << 'This cluster file will now be processed to compute representative subsamples for visualization.'
        message << 'You will receive an additional email once this has completed.'
        message << 'While subsamples are being computed, you will not be able to remove this cluster file or your metadata file.'
      end
    when :ingest_subsample
      cluster = ClusterGroup.find_by(study_id: study.id, study_file_id: study_file.id)
      message << "Subsampling has completed for #{cluster.name}"
      message << "Subsamples generated: #{cluster.subsample_thresholds_required.join(', ')}"
    when :ingest_differential_expression
      result = DifferentialExpressionResult.find_by(study:, study_file:)
      message << "Differential expression ingest completed for #{result.annotation_name}"
      message << "One-vs-rest comparisons: #{result.one_vs_rest_comparisons.join(', ')}" if result.one_vs_rest_comparisons.any?
      message << "Total pairwise comparisons: #{result.num_pairwise_comparisons}" if result.pairwise_comparisons.any?
    when :differential_expression
      message << "Differential expression calculations for #{params_object.cluster_name} have completed"
      message << "Selected annotation: #{params_object.annotation_name} (#{params_object.annotation_scope})"
    when :render_expression_arrays
      matrix_name = params_object.matrix_file_path.split('/').last
      matrix = study.expression_matrices.find_by(name: matrix_name)
      genes = Gene.where(study_id: study.id, study_file_id: matrix.id).count
      message << "Image Pipeline data pre-rendering completed for \"#{params_object.cluster_name}\""
      message << "Gene-level files created: #{genes}"
    when :image_pipeline
      complete_pipeline_runtime = TimeDifference.between(*get_image_pipeline_timestamps).humanize
      message << "Image Pipeline image rendering completed for \"#{params_object.cluster}\""
      message << "Complete runtime (data cache & image rendering): #{complete_pipeline_runtime}"
    when :ingest_anndata
      message << "AnnData file ingest has completed"
      if study_file.ann_data_file_info.has_expression
        genes = Gene.where(study_id: study.id, study_file_id: study_file.id).count
        message << "Gene-level entries created: #{genes}"
      end
      message << 'Clustering and metadata entries are being extracted as specified in your AnnData file.'
    end
    message
  end

  # generate a link to to the location of the cached copy of a file that failed to ingest
  # for use in admin error email contents
  #
  # * *returns*
  #   - (String) => HTML anchor tag with link to file directory that can be opened in the browser after authenticating
  def generate_bucket_browser_tag
    link = "#{study.google_bucket_url}/parse_logs/#{study_file.id}"
    '<a href="' + link + '">' + link + '</a>'
  end

  # format an error email message body for users
  #
  # * *params*
  #  - +email_type+ (Symbol) => Type of error email
  #                 :user => High-level error message intended for users, contains only messages and no stack traces
  #                 :dev => Debug-level error messages w/ stack traces intended for SCP team
  #
  # * *returns*
  #  - (String) => Contents of error messages for parse failure email
  def generate_error_email_body(email_type: :user)
    case email_type
    when :user
      error_contents = read_parse_logfile(user_error_filepath)
      message_body = "<p>'#{study_file.upload_file_name}' has failed during parsing.</p>"
    when :dev
      # only read first megabyte of error log to avoid email delivery failure
      error_contents = read_parse_logfile(dev_error_filepath, delete_on_read: false, range: 0..1.megabyte)
      message_body = "<p>The file '#{study_file.upload_file_name}' uploaded by #{user.email} to #{study.accession} failed to ingest.</p>"
      message_body += "<p>A copy of this file can be found at #{generate_bucket_browser_tag}</p>"
      message_body += "<p>Detailed logs and PAPI events as follows:"
    else
      error_contents = read_parse_logfile(user_error_filepath)
      message_body = "<p>'#{study_file.upload_file_name}' has failed during parsing.</p>"
    end

    if error_contents.present?
      message_body += "<h3>Errors</h3>"
      error_contents.each_line do |line|
        message_body += "#{line}<br />"
      end
    end

    if !error_contents.present? || email_type == :dev
      message_body += "<h3>Event Messages</h3>"
      message_body += "<ul>"
      event_messages.each do |e|
        message_body += "<li><pre>#{ERB::Util.html_escape(e)}</pre></li>"
      end
      message_body += "</ul>"
    end

    if study_file.file_type == 'Metadata'
      faq_link = "https://singlecell.zendesk.com/hc/en-us/articles/360060610092-Metadata-Validation-Errors-FAQ"
      message_body += "<h3>Common Errors for Metadata Files</h3>"
      message_body += "<p>You can view a list of common metadata validation errors and solutions in our documentation: "
      message_body += "<a href='#{faq_link}'>#{faq_link}</a></p>"
    end

    message_body += "<h3>Job Details</h3>"
    message_body += "<p>Study Accession: <strong>#{study.accession}</strong></p>"
    message_body += "<p>Study File ID: <strong>#{study_file.id}</strong></p>"
    message_body += "<p>Ingest Run ID: <strong>#{pipeline_name}</strong></p>"
    message_body += "<p>Command Line: <strong>#{command_line}</strong></p>"
    ingest_image_attributes = AdminConfiguration.get_ingest_docker_image_attributes
    message_body += "<p>Ingest Pipeline Docker image version: <strong>#{ingest_image_attributes[:tag]}</strong></p>"
    message_body
  end

  # log all event messages to the log for eventual searching
  #
  # * *yields*
  #   - Error log messages in event of parse failure
  def log_error_messages
    event_messages.each do |message|
      Rails.logger.error "#{pipeline_name} log: #{message}"
    end
  end

  # render out a list of annotations, or message stating why list cannot be shown (e.g. too long)
  #
  # *params*
  #  - +annotation_source+ (CellMetadatum/ClusterGroup) => Source of annotation, i.e. parent class instance
  #  - +cell_annotation+ (Hash) => Cell annotation from a ClusterGroup (defaults to nil)
  #
  # *returns*
  #  - (String) => String showing annotation information for email
  def get_annotation_message(annotation_source:, cell_annotation: nil)
    max_values = CellMetadatum::GROUP_VIZ_THRESHOLD.max
    case annotation_source.class
    when CellMetadatum
      message = "#{annotation_source.name}: #{annotation_source.annotation_type}"
      if annotation_source.values.size <= max_values || annotation_source.annotation_type == 'numeric'
        values = annotation_source.values.any? ? ' (' + annotation_source.values.join(', ') + ')' : ''
      else
        values = " (List too large for email -- #{annotation_source.values.size} values present, max is #{max_values})"
      end
      message + values
    when ClusterGroup
      message = "#{cell_annotation['name']}: #{cell_annotation['type']}"
      if cell_annotation['values'].size <= max_values || cell_annotation['type'] == 'numeric'
        values = cell_annotation['type'] == 'group' ? ' (' + cell_annotation['values'].join(',') + ')' : ''
      else
        values = " (List too large for email -- #{cell_annotation['values'].size} values present, max is #{max_values})"
      end
      message + values
    end
  end

  # helper to identify 'special action' jobs, such as differential expression or image pipeline jobs
  def special_action?
    SPECIAL_ACTIONS.include?(action.to_sym)
  end
end
