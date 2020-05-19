##
# IngestJob: lightweight wrapper around a PAPI ingest job with mappings to the study/file/user associated
# with this particular ingest job.  Handles polling for completion and notifying the user
##

class IngestJob
  include ActiveModel::Model

  # for getting the latest convention version
  include Api::V1::Concerns::ConventionSchemas

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

  extend ErrorTracker

  # number of tries to push a file to a study bucket
  MAX_ATTEMPTS = 3

  # Mappings between actions & models (for cleaning up data on re-parses)
  MODELS_BY_ACTION = {
      ingest_expression: Gene,
      ingest_cluster: ClusterGroup,
      ingest_cell_metadata: CellMetadatum,
      subsample: ClusterGroup
  }

  # Push a file to a workspace bucket in the background and then launch an ingest run and queue polling
  # Can also clear out existing data if necessary (in case of a re-parse)
  #
  # * *params*
  #   - +reparse+ (Boolean) => Indication of whether or not a file is being re-ingested, will delete existing documents
  #
  # * *yields*
  #   - (Google::Apis::GenomicsV2alpha1::Operation) => Will submit an ingest job in PAPI
  #   - (IngestJob.new(attributes).poll_for_completion) => Will queue a Delayed::Job to poll for completion
  #
  # * *raises*
  #   - (RuntimeError) => If file cannot be pushed to remote bucket
  def push_remote_and_launch_ingest(reparse: false)
    begin
      file_identifier = "#{self.study_file.bucket_location}:#{self.study_file.id}"
      if reparse
        Rails.logger.info "Deleting existing data for #{file_identifier}"
        rails_model = MODELS_BY_ACTION[action]
        rails_model.where(study_id: self.study.id, study_file_id: self.study_file.id).delete_all
        Rails.logger.info "Data cleanup for #{file_identifier} complete, now beginning Ingest"
      end
      # first check if file is already in bucket (in case user is syncing)
      remote = Study.firecloud_client.get_workspace_file(self.study.bucket_id, self.study_file.bucket_location)
      if remote.nil?
        Rails.logger.info "Preparing to push #{file_identifier} to #{self.study.bucket_id}"
        study.send_to_firecloud(study_file)
        is_pushed = false
        attempts = 1
        while !is_pushed && attempts <= MAX_ATTEMPTS
          remote = Study.firecloud_client.get_workspace_file(self.study.bucket_id, self.study_file.bucket_location)
          if remote.present?
            is_pushed = true
          else
            interval = 30 * attempts
            run_at = interval.seconds.from_now
            Rails.logger.error "Failed to push #{file_identifier} to #{self.study.bucket_id}; retrying at #{run_at}"
            attempts += 1
            self.delay(run_at: run_at).push_remote_and_launch_ingest(study: self.study, study_file: self.study_file,
                                                                     user: self.user, action: self.action, reparse: reparse)
          end
        end
      else
        is_pushed = true # file is already in bucket
      end
      if !is_pushed
        # push has failed 3 times, so exit and report error
        log_message = "Unable to push #{file_identifier} to #{self.study.bucket_id}"
        Rails.logger.error log_message
        raise RuntimeError.new(log_message)
      else
        Rails.logger.info "Remote found for #{file_identifier}, launching Ingest job"
        submission = ApplicationController.papi_client.run_pipeline(study_file: self.study_file, user: self.user, action: self.action)
        Rails.logger.info "Ingest run initiated: #{submission.name}, queueing Ingest poller"
        IngestJob.new(pipeline_name: submission.name, study: self.study, study_file: self.study_file,
                      user: self.user, action: self.action).poll_for_completion
      end
    rescue => e
      Rails.logger.error "Error in launching ingest of #{file_identifier}: #{e.class.name}:#{e.message}"
      error_context = ErrorTracker.format_extra_context(self.study, self.study_file, {action: self.action})
      ErrorTracker.report_exception(e, self.user, error_context)
    end
  end

  # Patch for using with Delayed::Job.  Returns true to mimic an ActiveRecord instance
  #
  # * *returns*
  #   - True::TrueClass
  def persisted?
    true
  end

  # Return an updated reference to this ingest run in PAPI
  #
  # * *returns*
  #   - (Google::Apis::GenomicsV2alpha1::Operation)
  def get_ingest_run
    ApplicationController.papi_client.get_pipeline(name: self.pipeline_name)
  end

  # Determine if this ingest run has done by checking current status
  #
  # * *returns*
  #   - (Boolean) => Indication of whether or not job has completed
  def done?
    self.get_ingest_run.done?
  end

  # Get all errors for ingest job
  #
  # * *returns*
  #   - (Google::Apis::GenomicsV2alpha1::Status)
  def error
    self.get_ingest_run.error
  end

  # Determine if a job failed by checking for errors
  #
  # * *returns*
  #   - (Boolean) => Indication of whether or not job failed via an unrecoverable error
  def failed?
    self.error.present?
  end

  # Get a status label for current state of job
  #
  # * *returns*
  #   - (String) => Status label
  def current_status
    if self.done?
      self.failed? ? 'Error' : 'Completed'
    else
      'Running'
    end
  end

  # Get the PAPI job metadata
  #
  # * *returns*
  #   - (Hash) => Metadata of PAPI job, including events, environment, labels, etc.
  def metadata
    self.get_ingest_run.metadata
  end

  # Get all the events for a given ingest job in chronological order
  #
  # * *returns*
  #   - (Array<Google::Apis::GenomicsV2alpha1::Event>) => Array of pipeline events, sorted by timestamp
  def events
    self.metadata['events'].sort_by! {|event| event['timestamp'] }
  end

  # Get all messages from all events
  #
  # * *returns*
  #   - (Array<String>) => Array of all messages in chronological order
  def event_messages
    self.events.map {|event| event['description']}
  end

  # Reconstruct the command line from the pipeline actions
  #
  # * *returns*
  #   - (String) => Deserialized command line
  def command_line
    command_line = ""
    self.metadata['pipeline']['actions'].each do |action|
      command_line += action['commands'].join(' ') + "\n"
    end
    command_line.chomp("\n")
  end

  # Get the total runtime of parsing from event timestamps
  #
  # * *returns*
  #   - (String) => Text representation of total elapsed time
  def get_total_runtime
    events = self.events
    start_time = DateTime.parse(events.first['timestamp'])
    completion_time = DateTime.parse(events.last['timestamp'])
    TimeDifference.between(start_time, completion_time).humanize
  end

  # Launch a background polling process.  Will check for completion, and if the pipeline has not completed
  # running, it will enqueue a new poller and exit to free up resources.  Defaults to checking every minute.
  # Job does not return anything, but will handle success/failure accordingly.
  #
  # * *params*
  #   - +run_at+ (DateTime) => Time at which to run new polling check
  def poll_for_completion(run_at: 1.minute.from_now)
    if self.done? && !self.failed?
      Rails.logger.info "IngestJob poller: #{self.pipeline_name} is done!"
      Rails.logger.info "IngestJob poller: #{self.pipeline_name} status: #{self.current_status}"
      self.study_file.update(parse_status: 'parsed')
      self.study.reload # refresh cached instance of study
      self.study_file.reload # refresh cached instance of study_file
      subject = "#{self.study_file.file_type} file: '#{self.study_file.upload_file_name}' has completed parsing"
      message = self.generate_success_email_array
      SingleCellMailer.notify_user_parse_complete(self.user.email, subject, message, self.study).deliver_now
      self.set_study_state_after_ingest
      self.study_file.invalidate_cache_by_file_type # clear visualization caches for file
    elsif self.done? && self.failed?
      Rails.logger.error "IngestJob poller: #{self.pipeline_name} has failed."
      # log errors to application log for inspection
      self.log_error_messages
      self.study_file.update(parse_status: 'failed')
      DeleteQueueJob.new(self.study_file).delay.perform
      Study.firecloud_client.delete_workspace_file(self.study.bucket_id, self.study_file.bucket_location)
      subject = "Error: #{self.study_file.file_type} file: '#{self.study_file.upload_file_name}' parse has failed"
      email_content = self.generate_error_email_body
      SingleCellMailer.notify_user_parse_fail(self.user.email, subject, email_content, self.study).deliver_now
    else
      Rails.logger.info "IngestJob poller: #{self.pipeline_name} is not done; queuing check for #{run_at}"
      self.delay(run_at: run_at).poll_for_completion
    end
  end

  # Set study state depending on what kind of file was just ingested
  # Does not return anything, but will set state and launch other jobs as needed
  #
  # * *yields
  # *
  #   - Study#set_cell_count, :set_study_default_options, Study#set_gene_count, and :set_study_initialized
  def set_study_state_after_ingest
    case self.study_file.file_type
    when 'Metadata'
      self.study.set_cell_count
      self.set_study_default_options
      self.launch_subsample_jobs
      # update search facets if convention data
      if self.study_file.use_metadata_convention
        SearchFacet.delay.update_all_facet_filters
      end
    when /Matrix/
      self.study.set_gene_count
    when 'Cluster'
      self.set_study_default_options
      self.launch_subsample_jobs
      self.set_subsampling_flags
    end
    self.set_study_initialized
  end

  # Set the default options for a study after ingesting Clusters/Cell Metadata
  #
  # * *yields*
  #   - Sets study default options for clusters/annotations
  def set_study_default_options
    case self.study_file.file_type
    when 'Metadata'
      if self.study.default_options[:annotation].blank?
        cell_metadatum = study.cell_metadata.keep_if {|meta| meta.can_visualize?}.first
        self.study.default_options[:annotation] = cell_metadatum.annotation_select_value
        if cell_metadatum.annotation_type == 'numeric'
          self.study.default_options[:color_profile] = 'Reds'
        end
      end
    when 'Cluster'
      if self.study.default_options[:cluster].nil?
        cluster = study.cluster_groups.by_name(self.study_file.name)
        self.study.default_options[:cluster] = cluster.name
        if self.study.default_options[:annotation].blank? && cluster.cell_annotations.any?
          annotation = cluster.cell_annotations.select {|annot| cluster.can_visualize_cell_annotation?(annot)}.first
          self.study.default_options[:annotation] = cluster.annotation_select_value(annotation)
          if annotation[:type] == 'numeric'
            self.study.default_options[:color_profile] = 'Reds'
          end
        end
      end
    end
    Rails.logger.info "Setting default options in #{self.study.name}: #{self.study.default_options}"
    self.study.save
  end

  # Set the study "initialized" attribute if all main models are populated
  #
  # * *yields*
  #   - Sets study initialized to True if needed
  def set_study_initialized
    if self.study.cluster_groups.any? && self.study.genes.any? && self.study.cell_metadata.any? && !self.study.initialized?
      self.study.update(initialized: true)
    end
  end

  # determine if subsampling needs to be run based on file ingested and current study state
  #
  # * *yields*
  #   - (IngestJob) => new ingest job for subsampling
  def launch_subsample_jobs
    case self.study_file.file_type
    when 'Cluster'
      # only subsample if ingest_cluster was just run, new cluster is > 1K points, and a metadata file is parsed
      cluster_ingested = self.action.to_sym == :ingest_cluster
      cluster = ClusterGroup.find_by(study_id: self.study.id, study_file_id: self.study_file.id)
      metadata_parsed = self.study.metadata_file.present? && self.study.metadata_file.parsed?
      if cluster_ingested && metadata_parsed && cluster.can_subsample? && !cluster.is_subsampling?
        # immediately set cluster.is_subsampling = true to gate race condition if metadata file just finished parsing
        cluster.update(is_subsampling: true)
        file_identifier = "#{self.study_file.bucket_location}:#{self.study_file.id}"
        Rails.logger.info "Launching subsampling ingest run for #{file_identifier} after #{self.action}"
        submission = ApplicationController.papi_client.run_pipeline(study_file: self.study_file, user: self.user,
                                                                    action: :ingest_subsample)
        Rails.logger.info "Subsampling run initiated: #{submission.name}, queueing Ingest poller"
        IngestJob.new(pipeline_name: submission.name, study: self.study, study_file: self.study_file,
                      user: self.user, action: :ingest_subsample).poll_for_completion
      end
    when 'Metadata'
      # subsample all cluster files that have already finished parsing.  any in-process cluster parses, or new submissions
      # will be handled by the above case.  Again, only subsample for completed clusters > 1K points
      metadata_identifier = "#{self.study_file.bucket_location}:#{self.study_file.id}"
      self.study.study_files.where(file_type: 'Cluster', parse_status: 'parsed').each do |cluster_file|
        cluster = ClusterGroup.find_by(study_id: self.study.id, study_file_id: cluster_file.id)
        if cluster.can_subsample? && !cluster.is_subsampling?
          # set cluster.is_subsampling = true to avoid future race conditions
          cluster.update(is_subsampling: true)
          file_identifier = "#{cluster_file.bucket_location}:#{cluster_file.id}"
          Rails.logger.info "Launching subsampling ingest run for #{file_identifier} after #{self.action} of #{metadata_identifier}"
          submission = ApplicationController.papi_client.run_pipeline(study_file: cluster_file, user: self.user,
                                                                      action: :ingest_subsample)
          Rails.logger.info "Subsampling run initiated: #{submission.name}, queueing Ingest poller"
          IngestJob.new(pipeline_name: submission.name, study: self.study, study_file: cluster_file,
                        user: self.user, action: :ingest_subsample).poll_for_completion
        end
      end
    end
  end

  # Set correct subsampling flags on a cluster after job completion
  def set_subsampling_flags
    case self.action
    when :ingest_subsample
      cluster_group = ClusterGroup.find_by(study_id: self.study.id, study_file_id: self.study_file.id)
      if cluster_group.is_subsampling? && cluster_group.find_subsampled_data_arrays.any?
        cluster_group.update(subsampled: true, is_subsampling: false)
      end
    end
  end

  # path to potential error file in study bucket
  #
  # * *returns*
  #   - (String) => String representation of path to parse error file
  def error_filepath
    "parse_logs/#{self.study_file.id}/errors.txt"
  end

  # path to potential warnings file in study bucket
  #
  # * *returns*
  #   - (String) => String representation of path to parse warnings file
  def warning_filepath
    "parse_logs/#{self.study_file.id}/warnings.txt"
  end

  # in case of an error, retrieve the contents of the warning or error file to email to the user
  # deletes the file immediately after being read
  #
  # * *params*
  #   - +filepath+ (String) => relative path of file to read in bucket
  #
  # * *returns*
  #   - (String) => Contents of file
  def read_parse_logfile(filepath)
    if Study.firecloud_client.workspace_file_exists?(self.study.bucket_id, filepath)
      file_contents = Study.firecloud_client.execute_gcloud_method(:read_workspace_file, 0, self.study.bucket_id, filepath)
      Study.firecloud_client.execute_gcloud_method(:delete_workspace_file, 0, self.study.bucket_id, filepath)
      file_contents.read
    end
  end

  # generates parse completion email body
  #
  # * *returns*
  #   - (Array) => List of message strings to print in a completion email
  def generate_success_email_array
    message = ["Total parse time: #{self.get_total_runtime}"]
    case self.study_file.file_type
    when /Matrix/
      genes = Gene.where(study_id: self.study.id, study_file_id: self.study_file.id).count
      message << "Gene-level entries created: #{genes}"
    when 'Metadata'
      if self.study_file.use_metadata_convention
        project_name = 'alexandria_convention' # hard-coded is fine for now, consider implications if we get more projects
        current_schema_version = get_latest_schema_version(project_name)
        schema_url = 'https://github.com/broadinstitute/single_cell_portal/wiki/Metadata-Convention'
        message << "This metadata file was validated against the latest <a href='#{schema_url}'>Metadata Convention</a>"
        message << "Convention version: <strong>#{project_name}/#{current_schema_version}</strong>"
      end
      cell_metadata = CellMetadatum.where(study_id: self.study.id, study_file_id: self.study_file.id)
      message << "Entries created:"
      cell_metadata.each do |metadata|
        unless metadata.nil?
          message << get_annotation_message(annotation_source: metadata)
        end
      end
    when 'Cluster'
      cluster = ClusterGroup.find_by(study_id: self.study.id, study_file_id: self.study_file.id)
      if self.action == :ingest_cluster
        message << "Cluster created: #{cluster.name}, type: #{cluster.cluster_type}"
        if cluster.cell_annotations.any?
          message << "Annotations:"
          cluster.cell_annotations.each do |annot|
            message << self.get_annotation_message(annotation_source: cluster, cell_annotation: annot)
          end
        end
        message << "Total points in cluster: #{cluster.points}"
      else
        message << "Subsampling has completed for #{cluster.name}"
        message << "Subsamples generated: #{cluster.subsample_thresholds_required.join(', ')}"
      end
    end
    message
  end

  # format an error email message body
  #
  # * *returns*
  #  - (String) => Contents of error messages for parse failure email
  def generate_error_email_body
    error_contents = self.read_parse_logfile(self.error_filepath)
    warning_contents = self.read_parse_logfile(self.warning_filepath)
    message_body = "<p>'#{self.study_file.upload_file_name}' has failed during parsing.</p>"
    if error_contents.present?
      message_body += "<h3>Errors</h3>"
      error_contents.each_line do |line|
        message_body += "#{line}<br />"
      end
    else
      message_body += "<h3>Event Messages (since no errors were shown)</h3>"
      message_body += "<ul>"
      self.event_messages.each do |e|
        message_body += "<li><pre>#{ERB::Util.html_escape(e)}</pre></li>"
      end
      message_body += "</ul>"
    end

    if warning_contents.present?
      message_body += "<h3>Warnings</h3>"
      warning_contents.each_line do |line|
        message_body += "#{line}<br />"
      end
    end
    message_body += "<h3>Details</h3>"
    message_body += "<p>Study Accession: <strong>#{self.study.accession}</strong></p>"
    message_body += "<p>Study File ID: <strong>#{self.study_file.id}</strong></p>"
    message_body += "<p>Ingest Run ID: <strong>#{self.pipeline_name}</strong></p>"
    message_body += "<p>Command Line: <strong>#{self.command_line}</strong></p>"
    message_body
  end

  # log all event messages to the log for eventual searching
  #
  # * *yields*
  #   - Error log messages in event of parse failure
  def log_error_messages
    self.event_messages.each do |message|
      Rails.logger.error "#{self.pipeline_name} log: #{message}"
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
      if annotation_source.values.size < max_values || annotation_source.annotation_type == 'numeric'
        values = annotation_source.values.any? ? ' (' + annotation_source.values.join(', ') + ')' : ''
      else
        values = " (List too large for email -- #{annotation_source.values.size} values present, max is #{max_values})"
      end
      message + values
    when ClusterGroup
      message = "#{cell_annotation['name']}: #{cell_annotation['type']}"
      if cell_annotation['values'].size < max_values || cell_annotation['type'] == 'numeric'
        values = cell_annotation['type'] == 'group' ? ' (' + cell_annotation['values'].join(',') + ')' : ''
      else
        values = " (List too large for email -- #{cell_annotation['values'].size} values present, max is #{max_values})"
      end
      message + values
    end
  end
end
