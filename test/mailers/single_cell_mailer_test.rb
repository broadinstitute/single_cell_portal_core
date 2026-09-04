require 'test_helper'

class SingleCellMailerTest < ActionMailer::TestCase

  before(:all) do
    ActionMailer::Base.perform_deliveries = true
    @user = FactoryBot.create(:admin_user, registered_for_firecloud: true, test_array: @@users_to_clean)
    @study = FactoryBot.create(
      :detached_study, user: @user, name_prefix: 'Noncompliant Study Test', created_at: 2.years.ago,
      test_array: @@studies_to_clean
    )
  end

  after(:all) do
    ActionMailer::Base.perform_deliveries = false
  end

  test "noncompliant_study_email" do
    email_params = { subject: 'Test Subject', contents: 'Test Contents' }
    email = SingleCellMailer.noncompliant_studies_email(@user, email_params).deliver_now
    assert_equal [@user.email], email.to
    assert email.body.encoded.include?('Test Contents')
  end
end