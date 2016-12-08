class ExpressionScoreController < ApplicationController
  before_action :set_expression_score, only: [:show]
  autocomplete :expression_score, :gene

  def index
    @expression_scores = ExpressionScore.all
  end

  def show
  end

  def get_autocomplete_items(parameters)
    items = mongoid_get_autocomplete_items(parameters)
    items = items.where(:study_id => params[:study_id])
  end

  private

  def set_expression_score
    @expression_score = ExpressionScore.find(params[:id])
  end
end

