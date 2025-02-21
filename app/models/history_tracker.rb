# Collection for tracking changes to tracked entities.  See https://github.com/mongoid/mongoid-history
class HistoryTracker
  include Mongoid::History::Tracker

  # get history track objects for all actions (or one particular action) on given model objects, within the date range
  # actions are create, update, destroy
  def self.trackers_by_date(model, action: nil, start_time: 1.day.ago, end_time: 0.days.ago)
    trackers = HistoryTracker.where(scope: model.to_s.underscore, :created_at.gt => start_time, :created_at.lt => end_time)
    if action.present?
      trackers = trackers.where(action: action)
    end
    trackers
  end

end
