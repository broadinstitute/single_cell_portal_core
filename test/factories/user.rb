# factory for users objects.
# Rough performance timing in local (non-dockerized) development suggests that crating a user
# using this factory takes ~0.1 seconds
FactoryBot.define do
  factory :user do
    transient do
      random_seed { SecureRandom.alphanumeric(4).upcase }
      # If specified, the created object will be added to the passed-in array after creation
      # this enables easy managing of a central list of objects to be cleaned up by a test suite
      test_array { nil }
    end
    email { "test.user.#{random_seed}@test.edu" }
    password { "test_password" }
    metrics_uuid { SecureRandom.uuid }
    after(:create) do |user, evaluator|
      if evaluator.test_array
        evaluator.test_array.push(user)
      end
    end

    factory :api_user do
      api_access_token {
                         {
                           access_token: "test-api-token-#{random_seed}",
                           expires_in: 3600, expires_at: Time.zone.now + 1.hour
                         }
                       }
    end
    factory :admin_user do
      admin { true }
      access_token {
        {
            access_token: "test-admin-token-#{random_seed}",
            expires_in: 3600, expires_at: Time.zone.now + 1.hour
        }
      }
      api_access_token {
        {
            access_token: "test-admin-token-#{random_seed}",
            expires_in: 3600, expires_at: Time.zone.now + 1.hour
        }
      }
    end
  end
end
