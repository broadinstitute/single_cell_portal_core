class CreateDotPlotGeneCollection < Mongoid::Migration
  def self.up
    # since these documents will be created by scp-ingest-pipeline, the collection needs to exist first to
    # prevent errors when the job tries to create them
    # Only create if it doesn't already exist
    DotPlotGene.collection.create unless DotPlotGene.collection.database.collection_names.include?('dot_plot_genes')
  end

  def self.down
    DotPlotGene.collection.drop
  end
end
