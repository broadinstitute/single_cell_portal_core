# delayed_job_accessor.rb

module DelayedJobAccessor

  # Classes allowed to access jobs from the queue
  # only applies to job classes that queue jobs in the future (DeleteQueueJob, CacheRemovalJob are run on demand)
  ALLOWED_JOB_TYPES = [IngestJob, UploadCleanupJob].freeze

  # find a Delayed::Job instance of a particular class, and refine by an associated object
  #
  # * *params*
  #   - job_class (Class) => Class of job to find, such as UploadCleanupJob or IngestJob
  #   - associated_object (String) => Instance of SCP model to load attributes from
  #
  # * *returns*
  #   - (Array<Delayed::Job>) => Array of matching jobs
  #
  # * *raises*
  #   - (ArgumentError) => If job_class is not one of the ALLOWED_JOB_TYPES, which are all SCP model-based
  def self.find_jobs_by_handler_type(job_class, associated_object)
    matching_jobs = []
    raise ArgumentError.new("#{job_class} is not an approved job class: #{ALLOWED_JOB_TYPES}") if !ALLOWED_JOB_TYPES.include?(job_class)
    Delayed::Job.all.each do |job|
      handler = dump_job_handler(job)
      matching_jobs << job if match_handler_to_object(handler, job_class, associated_object)
    end
    matching_jobs
  end

  # decode YAML Delayed::Job handler into queued object
  #
  # * *params*
  #   - job (Delayed::Job) => Instance of Delayed::Job
  #
  # * *returns*
  #   - (Struct) => Struct representing original queued task
  def self.dump_job_handler(job)
    YAML.unsafe_load(job.handler)
  end

  # match a job handler to the specified object instance
  #
  # * *params*
  #   - handler (Struct) => Decoded Delayed::Job handler from dump_job_handler
  #   - job_class (Class) => Class of job to find, such as UploadCleanupJob, DeleteQueueJob, CacheRemovalJob, IngestJob
  #   - associated_object (String) => Instance of SCP model to load attributes from
  #
  # * *returns*
  #   - (Boolean) => T/F on match of instance by object ID
  def self.match_handler_to_object(handler, job_class, associated_object)
    # snake-case version of object class name, e.g. StudyFile => 'study_file'
    object_key = associated_object.class.name.underscore
    if handler.is_a?(job_class)
      matching_object = handler.send(object_key)
    elsif handler.is_a?(Delayed::PerformableMethod) && handler.object.is_a?(job_class)
      # handle case where a performable method was queued, and not an instance of a class
      matching_object = handler.object.send(object_key)
    end
    # match on object ID, or return false if no object was found
    matching_object.present? ? matching_object.dig('attributes', '_id') == associated_object.id : false
  end
end
