class CreateDotPlotGeneCollection < Mongoid::Migration
  def self.up
    # since these documents will be created by scp-ingest-pipeline, the collection needs to exist first to
    # prevent errors when the job tries to create them
    DotPlotGene.collection.create
  end

  def self.down
    DotPlotGene.collection.drop
  end
end
