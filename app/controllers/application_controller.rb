class ApplicationController < ActionController::Base
  # Prevent CSRF attacks by raising an exception.
  # For APIs, you may want to use :null_session instead.
  protect_from_forgery with: :exception

  before_action :populate_studies

  # get all studies, needed for nav and home page downloads
  def populate_studies
    @studies = Study.order('name ASC')
  end
end
