# helper to retrieve ingest pipeline runs from delayed_job & PAPI queues in test environment

# get instance of Delayed::Job for an ingest pipeline submission
def get_ingest_delayed_job(study_file)
  jobs = DelayedJobAccessor.find_jobs_by_handler_type(IngestJob, study_file)
  jobs.sort_by { |job| job.created_at }.last
end

# get PAPI instance for an ingest pipeline submission
def get_ingest_pipeline_run(study_file)
  dj_instance = get_ingest_delayed_job(study_file)
  handler = DelayedJobAccessor.dump_job_handler(dj_instance)
  pipeline_name = handler['pipeline_name']
  ApplicationController.papi_client.get_pipeline(name: pipeline_name)
end
