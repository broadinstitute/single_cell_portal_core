# helper to restore user access tokens on test teardown to prevent successive downstream failures
def reset_user_tokens
  User.all.each do |user|
    token = { access_token: SecureRandom.uuid, expires_in: 3600, expires_at: Time.zone.now + 1.hour }
    user.update!(access_token: token, api_access_token: token)
    user.update_last_access_at!
  end
end

# since GCS buckets only allow a small number of "test" emails, we need to reuse one for simplicity
def gcs_bucket_test_user
  User.find_or_create_by(email: 'user@example.net') do |user|
    user.uid = rand(10000..99999)
    user.password = SecureRandom.uuid
    user.metrics_uuid = SecureRandom.uuid
    TosAcceptance.create(email: user.email) unless TosAcceptance.accepted?(user)
  end
end
