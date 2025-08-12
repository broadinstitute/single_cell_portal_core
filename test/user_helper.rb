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
  create_gcs_user(email: 'user@example.net')
end

def gcs_bucket_sharing_user
  create_gcs_user(email: 'user@test.com', admin: false)
end

def create_gcs_user(email: nil, admin: true, random_seed: SecureRandom.alphanumeric(4).upcase)
  token = {
    access_token: "test-token-#{random_seed}",
    expires_in: 3600, expires_at: Time.zone.now + 1.hour
  }
  User.find_or_create_by(email:) do |user|
    user.admin = admin
    user.uid = rand(10000..99999)
    user.password = SecureRandom.uuid
    user.metrics_uuid = SecureRandom.uuid
    user.access_token = token
    user.api_access_token = token
    TosAcceptance.create(email: user.email) unless TosAcceptance.accepted?(user)
  end
end
