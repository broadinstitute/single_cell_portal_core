##
# PortalUtils: generic class with server stats/maintenance methods
#
# note: all instances of :start_date and :end_date are inclusive
##
class SummaryStatsUtils
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

  # find out all ingest jobs run in a given time period
  # since the "filter" parameter for list_project_operations doesn't work, check dates manually.
  # defaults to current day
  def self.ingest_run_count(start_date: Time.zone.today, end_date: Time.zone.today + 1.day)
    # make sure we only look at instances of runs for this schema (e.g. exclude test from staging/prod)
    schema = Mongoid::Config.clients["default"]["database"]
    ingest_jobs = 0
    jobs = ApplicationController.papi_client.list_pipelines
    all_from_range = false
    date_range = start_date..end_date
    until all_from_range
      jobs.operations.each do |job|
        if job.metadata['startTime'].nil?
          next
        end
        submission_date = Time.zone.parse(job.metadata['startTime']).to_date
        # use `dig` to avoid NoMethodError
        database_name = job.metadata.dig('pipeline', 'environment', 'DATABASE_NAME')
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
        jobs = ApplicationController.papi_client.list_pipelines(page_token: jobs.next_page_token)
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
