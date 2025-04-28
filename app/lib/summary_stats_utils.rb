##
# PortalUtils: generic class with server stats/maintenance methods
#
# note: all instances of :start_date and :end_date are inclusive
##
class SummaryStatsUtils
  # amount of time where a private study is considered 'defunct' if there is no file activity
  PRIVATE_STUDY_CUTOFF = 1.year.ago.to_date.freeze

  # soft cap for data storage
  DATA_STORAGE_CAP = 200.gigabytes

  # minumum amount of data in GB before we consider cleanup, i.e. 1/2 TB
  # this equates to $60/year, or $5/month
  MINIMUM_GB_FOR_CLEANUP = 0.01.freeze

  # price in $ per GB/YR of GCS bucket storage
  YEARLY_COST_PER_GB = 0.24.freeze

  include Sys
  # get a snapshot of user counts/activity up to a given date
  # will give count of users as of that date, and number of active users on that date
  def self.daily_total_and_active_user_counts(end_date: Time.zone.today)
    # make sure to make end_date one day forward to include any users that were created on cutoff date
    next_day = end_date + 1.day
    total_users = User.where(:created_at.lte => next_day).count
    active_users = User.where(:current_sign_in_at => (end_date..next_day)).count
    {total: total_users, active: active_users}
  end

  # get a count of all submissions launch from the portal in a given 2 week period
  # defaults to a time period of the last two weeks from right now
  def self.analysis_submission_count(start_date: DateTime.now - 2.weeks, end_date: DateTime.now)
    AnalysisSubmission.where(:submitted_on => (start_date..end_date), submitted_from_portal: true).count
  end

  # get a count of all studies created on the requested day
  def self.daily_study_creation_count(end_date: Time.zone.today)
    Study.where(:created_at => (end_date..(end_date + 1.day))).count
  end

  # get a count of all studies, public studies, and also which of those have compliant metadata
  def self.study_counts
    studies = Study.where(queued_for_deletion: false)
    public = studies.where(public: true).pluck(:id)
    {
      all: studies.count,
      public: public.count,
      compliant: StudyFile.any_of(
        { file_type: 'Metadata' },
        { file_type: 'AnnData', 'ann_data_file_info.has_metadata' => true }
      ).where(use_metadata_convention: true, :study_id.in => public).count
    }
  end

  # get a weekly count of users that have logged into the portal
  def self.weekly_returning_users
    today = Date.today
    one_week_ago = today - 1.weeks
    user_count = User.where(:last_sign_in_at.gte => one_week_ago, :last_sign_in_at.lt => today)
                     .or(:current_sign_in_at.gte => one_week_ago, :current_sign_in_at.lt => today).count
    {count: user_count, description: "Count of returning users from #{one_week_ago} to #{today}"}
  end

  # perform a sanity check to look for any missing files in remote storage
  # returns a list of all missing files for entire portal for use in nightly_server_report
  def self.storage_sanity_check
    missing_files = []
    valid_accessions = Study.where(queued_for_deletion: false, detached: false).pluck(:accession)
    valid_accessions.each do |accession|
      study = Study.find_by(accession: accession)
      begin
        study_missing = study.verify_all_remotes
        missing_files += study_missing if study_missing.any?
      rescue => e
        # check if the bucket or the workspace is missing and mark study accordingly
        study.set_study_detached_state(e)
        ErrorTracker.report_exception(e, nil, {})
        Rails.logger.error  "Error in retrieving remotes for #{study.name}: #{e.message}"
        missing_files << {
          filename: 'N/A', study: study.name, owner: study.user&.email, reason: "Error retrieving remotes: #{e.message}"
        }
      end
    end
    missing_files
  end

  # disk usage stats
  def self.disk_usage
    stat = Filesystem.stat(Rails.root.to_s)
    {
        total_space: stat.bytes_total,
        space_used: stat.bytes_used,
        space_free: stat.bytes_free,
        percent_used: (100 * (stat.bytes_used / stat.bytes_total.to_f)).round,
        mount_point: stat.path
    }
  end

  # get a list of studies that are out of compliance with the data retention policy
  def self.data_retention_report
    start_time = Time.now
    non_compliant_studies = {}
    studies = Study.where(
      :created_at.lte => PRIVATE_STUDY_CUTOFF, detached: false, firecloud_project: FireCloudClient::PORTAL_NAMESPACE
    )
    Parallel.map(studies, in_threads: 20) do |study|
      puts "checking #{study.accession}"
      client = FireCloudClient.new
      begin
        bucket = client.get_workspace_bucket(study.bucket_id)
        next if bucket.nil?

        remotes = bucket.files
        next if remotes.empty?

        batches = 0
        bytes, last_created = bytes_and_last_created_for(remotes)
        while remotes.next? && batches <= 9
          batches += 1
          remotes = remotes.next
          bytes, last_created = bytes_and_last_created_for(remotes, bytes:, last_created:)
        end

        total_gb = (bytes / 1024 / 1024 / 1024.0).floor(2)
        more_files = remotes.next?
        unless meets_data_retention_policy?(study, bytes, more_files:)
          puts "#{study.accession} candidate for removal"
          non_compliant_studies[study.accession] = {
            accession: study.accession,
            name: study.name,
            owner: study.user&.email,
            created_at: study.created_at,
            public: study.public,
            has_files: study.study_files.any? || study.directory_listings.are_synced.any?,
            visualizations: study.can_visualize?,
            last_created:,
            total_gb:,
            total_cost: (total_gb * YEARLY_COST_PER_GB).floor(2),
            more_files:,
            reason: data_retention_violation(study, bytes, more_files:)
          }
        end
        non_compliant_studies
      rescue Google::Cloud::PermissionDeniedError => e
        ErrorTracker.report_exception(e, nil, { study: })
      end
    end
    end_time = Time.now
    puts "Completed, #{studies.count} studies evaluated, total runtime: " \
           "#{TimeDifference.between(start_time, end_time).humanize}"
    non_compliant_studies
  end

  # get byte count and data of last file creation for a batch of remotes
  def self.bytes_and_last_created_for(remotes, bytes: 0, last_created: nil)
    created = last_created || remotes.first.created_at
    remotes.map do |remote|
      bytes += remote.size
      created = created >= remote.created_at ? created : remote.created_at
    end
    [bytes, created.in_time_zone]
  end

  # determine if a study complies the data retention policy
  # must be less than 200GB of storage and public, or private and less than 1 year old
  # any study with more than 10K files in the bucket will automatically be flagged as we can't accurately
  # gauge storage costs
  def self.meets_data_retention_policy?(study, total_bytes, more_files: false)
    if study.public
      total_bytes <= DATA_STORAGE_CAP && !more_files
    else
      study.created_at >= PRIVATE_STUDY_CUTOFF && total_bytes <= DATA_STORAGE_CAP && !more_files
    end
  end

  # give a reason for why a study doesn't meet the data retention policy
  def self.data_retention_violation(study, total_bytes, more_files: false)
    return 'too many files' if more_files

    if more_files
      'file count exception'
    elsif total_bytes >= DATA_STORAGE_CAP
      'storage cap violation'
    elsif !study.public && study.created_at <= PRIVATE_STUDY_CUTOFF
      'old private study'
    else
      'no violation detected'
    end
  end

  # find out all ingest jobs run in a given time period
  # since the "filter" parameter for list_project_location_jobs doesn't work, check dates manually.
  # defaults to current day
  def self.ingest_run_count(start_date: Time.zone.today, end_date: Time.zone.today + 1.day)
    # make sure we only look at instances of runs for this schema (e.g. exclude test from staging/prod)
    schema = Mongoid::Config.clients.dig('default', 'database')
    ingest_jobs = 0
    client = ApplicationController.batch_api_client
    jobs = client.list_jobs
    return ingest_jobs if jobs.jobs.blank?

    all_from_range = false
    date_range = start_date..end_date
    until all_from_range
      jobs.jobs.each do |job|
        if job.create_time.nil?
          next
        end
        submission_date = Time.zone.parse(job.create_time).to_date
        database_name = client.get_job_environment(job:)&.[]('DATABASE_NAME')
        if submission_date > end_date && submission_date > start_date
          next
        elsif date_range === submission_date
          ingest_jobs += 1 if schema == database_name
        else
          all_from_range = true
          break
        end
      end
      if all_from_range || jobs.next_page_token.blank?
        break
      else
        jobs = client.list_jobs(page_token: jobs.next_page_token)
      end
    end
    ingest_jobs
  end

  # returns an array of hashes, each with title, accession, study_owner,
  # one entry in the array for each study that has been deleted during the time frame
  def self.deleted_studies_info(start_date: Time.zone.today, end_date: Time.zone.today + 1.day)
    deletions = HistoryTracker.trackers_by_date(Study, action: 'destroy', start_time: start_date, end_time: end_date)
    deletion_info = deletions.map do |tracker|
      {
        title: tracker.original['name'],
        accession: tracker.original['accession'],
        study_owner: User.find_by(id: tracker.original['user_id']).try(:email)
      }
    end
    deletion_info
  end

  # returns an array of hashes, each with title, accession, study_owner, and other_studies.
  # one entry in the array for each study that has been created during the time frame
  def self.created_studies_info(start_date: Time.zone.today, end_date: Time.zone.today + 1.day)
    creations = HistoryTracker.trackers_by_date(Study, action: 'create', start_time: start_date, end_time: end_date)
    creation_info = creations.map do |tracker|
      user = User.find(tracker.modified['user_id'])
      study = Study.find(tracker.association_chain.first['id'])
      other_studies = []
      if user.present?
        other_studies = Study.where(user_id: user.id).pluck(:accession, :created_at)
      end
      info = {
        title: tracker.modified['name'],
        accession: tracker.modified['accession'],
        study_owner: user.try(:email),
        other_studies: other_studies
      }
      if study.present? # study is not already deleted
        types_array = study.study_files.pluck(:file_type)
        # get a hash of the number of each file type present
        info[:file_types] = types_array.group_by(&:itself).transform_values!(&:size)
      end
      info
    end
    creation_info
  end

  # returns an array of hashes, each with title, accession, owner, and updates
  # one entry in the array for each study that has been updated during the time frame
  # the 'updates' attribute is a hash of properties to counts of times that property was updated
  # Updates to study files are tracked as a 'file updates' property in that hash
  # by default, this excludes reporting on studies that have been created/deleted within the time period
  def self.updated_studies_info(start_date: Time.zone.today, end_date: Time.zone.today + 1.day, exclude_create_delete: true)
    updates = HistoryTracker.trackers_by_date(Study, action: 'update', start_time: start_date, end_time: end_date).to_a
    excluded_ids = []
    # we typically exclude created and deleted studies from this report, since those are handled separately
    # however allowing their inclusion can help for testing
    if exclude_create_delete
      creates_and_deletes = HistoryTracker.where(scope: 'study', :created_at.gt => start_date, :created_at.lt => end_date, :action.in => ['create', 'delete'])
      excluded_ids = creates_and_deletes.map{ |tracker| tracker.association_chain.first['id'] }
    end

    # for each study id, assemble a hash of property names to # of times they've been modified
    updates_by_id = {}
    updates.each do |update|
      study_id = update.association_chain.first['id'].to_s
      if excluded_ids.to_s.exclude?(study_id)
        updates_by_id[study_id] ||= {}
        update['modified'].keys.each {|key| updates_by_id[study_id][key] = updates_by_id[study_id][key].to_i + 1 }
      end
    end

    # now update the hash with the number of times a study file has been updated
    study_file_updates(excluded_ids, updates_by_id, start_date: start_date, end_date: end_date)

    update_info = updates_by_id.map do |id, value|
      study = Study.find(id)
      if study.present?
        {
          title: study.name,
          study_owner: study.user.try(:email),
          accession: study.accession,
          updates: value
        }
      else
        nil
      end
    end.compact
    update_info
  end

  # returns a hash of study ids to the number of file updates performed
  # this number is stored in a "file updates" property on the hash, so it can be merged with other
  # update properties collected and passed in via the updates_by_id argument
  def self.study_file_updates(excluded_study_ids, updates_by_id={}, start_date: Time.zone.today, end_date: Time.zone.today + 1.day)
    file_updates = HistoryTracker.trackers_by_date(StudyFile, start_time: start_date, end_time: end_date).to_a
    file_updates.each do |update|
      study_file_id = update.association_chain.first['id'].to_s
      study_file = StudyFile.find_by(id: study_file_id)
      study_id = nil
      if study_file.present?
        study_id = study_file.study_id.to_s
      elsif update['action'] == 'destroy'
        study_id = update['original']['study_id'].to_s
      end
      if study_id.present? && excluded_study_ids.to_s.exclude?(study_id)
        updates_by_id[study_id] ||= {}
        updates_by_id[study_id]['file updates'] = updates_by_id[study_id]['file updates'].to_i + 1
      end
    end
    updates_by_id
  end
end
