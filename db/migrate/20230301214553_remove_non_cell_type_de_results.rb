class RemoveNonCellTypeDeResults < Mongoid::Migration
  def self.up
    DifferentialExpressionResult.where(
      :annotation_name.not => DifferentialExpressionService::CELL_TYPE_MATCHER
    ).map do |result|
      Rails.logger.info "deleting DE result for #{result.annotation_identifier} in #{result.study.accession}"
      result.delay.destroy # run destroy in the background to prevent migration from delaying deployment
    end
  end

  def self.down
    # we can't regenerate the results without re-running the entire job, so nothing to do here
    # results can be manually re-run if we decide later that we want them again
  end
end
