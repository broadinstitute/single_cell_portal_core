json.study_shares @study.study_shares.to_a, partial: 'api/v1/study_shares/study_share', as: :study_share
json.study_files do
  json.unsynced @unsynced_files, partial: 'api/v1/study_files/study_file_sync', as: :study_file
  json.orphaned @orphaned_study_files, partial: 'api/v1/study_files/study_file_sync', as: :study_file
  json.synced @synced_study_files, partial: 'api/v1/study_files/study_file_sync', as: :study_file
end
json.directory_listings do
  json.unsynced @unsynced_directories, partial: 'api/v1/directory_listings/directory_listing', as: :directory_listing
  json.synced @synced_directories, partial: 'api/v1/directory_listings/directory_listing', as: :directory_listing
end
json.set! :page_token, @next_page
json.set! :remaining_files, @remaining_files
if @next_page
  json.set! :next_page, sync_batch_api_v1_study_url(
    @study, page_token: @next_page, host: RequestUtils.get_hostname
  )
end
