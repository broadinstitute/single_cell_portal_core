class RenameObservedValues < Mongoid::Migration
  def self.up
    DifferentialExpressionResult.all.each do |result|
      result.rename(observed_values: :one_vs_rest_comparisons)
    end
  end

  def self.down
    DifferentialExpressionResult.all.each do |result|
      result.rename(one_vs_rest_comparisons: :observed_values)
    end
  end
end
