require "test_helper"

class ParseUtilsTest < ActiveSupport::TestCase

  def setup
    @study = Study.first
  end

  # test parsing 10X CellRanger output
  def test_cell_ranger_expression_parse
    puts "#{File.basename(__FILE__)}: #{self.method_name}"

    # load study files
    matrix = @study.study_files.by_type('MM Coordinate Matrix').first
    genes = @study.study_files.by_type('10X Genes File').first
    barcodes_file = @study.study_files.by_type('10X Barcodes File').first

    # control values
    @expected_genes = File.open(genes.upload.path).readlines.map {|line| line.split.map(&:strip)}
    @expected_cells = File.open(barcodes_file.upload.path).readlines.map(&:strip)
    matrix_file = File.open(matrix.upload.path).readlines
    matrix_file.shift(3) # discard header lines
    expressed_gene_idx = matrix_file.map {|line| line.split.first.strip.to_i}
    @expressed_genes = expressed_gene_idx.map {|idx| @expected_genes[idx - 1].last}

    # initiate parse

    user = User.first
    puts 'Parsing 10X GRCh38 output...'
    ParseUtils.cell_ranger_expression_parse(@study, user, matrix, genes, barcodes_file, {skip_upload: true})
    puts 'Parse of 10X GRCh38 complete'
    # validate that the expected significant values have been created
    @expected_genes.each do |entry|
      gene_id, gene_name = entry
      gene = @study.genes.find_by(name: gene_name)
      assert gene_name == gene.name, "Gene names do not match: #{gene_name}, #{gene.name}"
      assert gene_id == gene.gene_id, "Gene IDs do not match: #{gene_id}, #{gene.gene_id}"
      # if this gene is expected to have expression, then validate the score is correct
      if @expressed_genes.include?(gene_name)
        expected_value = @expressed_genes.index(gene_name) + 1
        cell_name = gene.scores.keys.first
        assert @expected_cells.include?(cell_name), "Cell name '#{cell_name}' was not from control list: #{@expected_cells}"
        value = gene.scores.values.first
        assert value == expected_value, "Did not find correct score value for #{gene.name}:#{cell_name}, expected #{expected_value} but found #{value}"
      end
    end
    puts "#{File.basename(__FILE__)}: #{self.method_name} successful!"
  end

  # test that sparse matrix parsing validates coordinate matrix sort order correctly
  def test_sparse_matrix_sort_check
    puts "#{File.basename(__FILE__)}: #{self.method_name}"

    # create a test study and add matrix files and bundle
    user = User.first
    study = Study.create(name: 'Negative Testing Study', firecloud_project: ENV['PORTAL_NAMESPACE'], user_id: user.id)
    user = User.first
    mm_coord_file = StudyFile.create!(name: 'GRCh38/test_bad_matrix.mtx', upload: File.open(Rails.root.join('test', 'test_data', 'GRCh38', 'test_bad_matrix.mtx')),
                                      file_type: 'MM Coordinate Matrix', study_id: study.id)
    genes_file = StudyFile.create!(name: 'GRCh38/test_genes.tsv', upload: File.open(Rails.root.join('test', 'test_data', 'GRCh38', 'test_genes.tsv')),
                                   file_type: '10X Genes File', study_id: study.id, options: {matrix_id: mm_coord_file.id.to_s})
    barcodes_file = StudyFile.create!(name: 'GRCh38/barcodes.tsv', upload: File.open(Rails.root.join('test', 'test_data', 'GRCh38', 'barcodes.tsv')),
                                 file_type: '10X Barcodes File', study_id: study.id, options: {matrix_id: mm_coord_file.id.to_s})

    study_file_bundle = study.study_file_bundles.build(bundle_type: mm_coord_file.file_type)
    bundle_payload = StudyFileBundle.generate_file_list(mm_coord_file)
    study_file_bundle.original_file_list = bundle_payload
    study_file_bundle.save!

    # gotcha for refreshing matrix file after creating bundle to pick up association
    mm_coord_file.reload

    begin
      puts 'Parsing 10X incorrectly sorted matrix...'
      ParseUtils.cell_ranger_expression_parse(study, user, mm_coord_file, genes_file, barcodes_file, {skip_upload: true, sync: true})
    rescue => e
      assert e.is_a?(StandardError), "Did not raise the correct error, expected StandardError but found #{e.class}"
      assert e.message.starts_with?('Your input matrix is not sorted in the correct order.'), "Error message did not specify incorrect sort order: #{e.message}"
      assert study.genes.count == 0, "Should not have saved any genes, found #{study.genes.count}"
    end

    puts "#{File.basename(__FILE__)}: #{self.method_name} successful!"
  end
end
