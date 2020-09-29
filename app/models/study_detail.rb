class StudyDetail
  include Mongoid::Document
  include Mongoid::Timestamps

  belongs_to :study

  field :full_description, type: String, default: ''

  after_save :set_study_description_text

  def plain_text_description
    ActionController::Base.helpers.strip_tags(self.full_description)
  end

  private

  # sets plain-text study description on saves
  # study.reload must be called to refresh the state of the association as it may have changed during
  # the course of the callback, otherwise validation failures or infinite recursion can occur
  def set_study_description_text
    study_object = self.study
    study_object.reload
    study_object.description = self.plain_text_description
    study_object.save!
  end
end
