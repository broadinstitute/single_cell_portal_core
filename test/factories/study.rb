FactoryBot.define do
  # gets a study object, defaulting to the first user found.  If name_prefix and description_prefix are
  # used instead of name/description, FactoryBot will auto-append unique suffixes and debug helpers to them.
  factory :study do
    transient do
      # If specified, the created study will be added to the passed-in array after creation
      # this enables easy managing of a central list of studies to be cleaned up by a test suite
      test_array { nil }
      name_prefix { 'FactoryBot Study' }
      description_prefix { ' ' }
    end
    name { name_prefix + " #{SecureRandom.alphanumeric(5)}" }
    description do
      calling_test =  caller.find { |s| /_test.rb/ =~ s }
      "#{description_prefix} Test study created by FactoryBot at #{Time.current}. #{calling_test}"
    end
    public { true }
    data_dir { '/tmp' }
    user { User.first }
    after(:create) do |study, evaluator|
      if evaluator.test_array
        evaluator.test_array.push(study)
      end
    end
    # create a study but mark as detached, so a Terra workspace is not created
    factory :detached_study do
      detached { true }
      bucket_id { SecureRandom.alphanumeric(16) } # needed to prevent test errors when mocking/stubbing GCS calls
    end
  end
end
