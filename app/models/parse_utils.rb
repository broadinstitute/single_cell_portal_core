require 'rubygems/package' # for tar reader
class ParseUtils
  extend ErrorTracker

  # parse a 10X gene-barcode matrix file triplet (input matrix must be sorted by gene indices)
  def self.cell_ranger_expression_parse(study, user, matrix_study_file, genes_study_file, barcodes_study_file, opts={})
    begin
      start_time = Time.zone.now
      # localize files
      Rails.logger.info "#{Time.zone.now}: Parsing gene-barcode matrix source data files for #{study.name} with the following options: #{opts}"
      study.make_data_dir
      Rails.logger.info "#{Time.zone.now}: Localizing output files & creating study file entries from 10X CellRanger source data for #{study.name}"

      # localize files if necessary, otherwise open newly uploaded files. check to make sure a local copy doesn't already exists
      # as we may be uploading files piecemeal from upload wizard
      matrix_file = localize_study_file(matrix_study_file, study)
      genes_file = localize_study_file(genes_study_file, study)
      barcodes_file = localize_study_file(barcodes_study_file, study)

      # next, check if this is a re-parse job, in which case we need to remove all existing entries first
      if opts[:reparse]
        Gene.where(study_id: study.id, study_file_id: matrix_study_file.id).delete_all
        DataArray.where(study_id: study.id, study_file_id: matrix_study_file.id).delete_all
        DataArray.where(name: "#{matrix_file.name} Cells", array_type: 'cells', linear_data_type: 'Study',
                        linear_data_id: study.id).delete_all
        matrix_study_file.invalidate_cache_by_file_type
      end

      # process the genes file to concatenate gene names and IDs together (for differentiating entries with duplicate names)
      raw_genes = genes_file.readlines.map(&:strip)
      @genes = []
      raw_genes.each do |row|
        vals = row.split(/[\t,\s]/) # split on tabs, commas, or whitespace
        if vals.size == 1
          @genes << vals.first.strip
        else
          gene_id, gene_name = vals.map(&:strip)
          @genes << [gene_name, gene_id]
        end
      end

      # read barcodes file
      @barcodes = barcodes_file.readlines.map(&:strip)

      # close files
      genes_file.close
      barcodes_file.close

      # validate that barcodes list does not have any repeated values
      existing_cells = study.all_expression_matrix_cells
      uniques = @barcodes - existing_cells

      unless uniques.size == @barcodes.size
        repeats = @barcodes - uniques
        raise StandardError, "You have re-used the following cell names that were found in another expression matrix in your study (cell names must be unique across all expression matrices): #{repeats.join(', ')}"
      end

      # open matrix file and read contents
      Rails.logger.info "#{Time.zone.now}: Reading gene/barcode/matrix file contents for #{study.name}"
      m_header_1 = matrix_file.readline.split.map(&:strip)
      valid_headers = %w(%%MatrixMarket matrix coordinate)
      unless m_header_1.first == valid_headers.first && m_header_1[1] == valid_headers[1] && m_header_1[2] == valid_headers[2]
        raise StandardError, "Your input matrix is not a Matrix Market Coordinate Matrix (header validation failed).  The first line should read: #{valid_headers.join(' ')}, but found #{m_header_1}"
      end

      scores_header = matrix_file.readline.strip
      while scores_header.start_with?('%')
        # discard empty comment lines
        scores_header = matrix_file.readline.strip
      end

      # containers for holding data yet to be saved to database
      @gene_documents = []
      @data_arrays = []
      @count = 0
      @child_count = 0

      # read first line manually and initialize containers for storing temporary data yet to be added to documents
      Rails.logger.info "#{Time.zone.now}: Initializing data structures from 10X CellRanger source data for #{study.name}"
      line = matrix_file.readline.strip
      gene_index, barcode_index, expression_score = parse_line(line)
      @last_gene_index, @current_gene = initialize_new_gene(study, gene_index, matrix_study_file)
      @current_barcodes = [@barcodes[barcode_index]]
      @current_expression = [expression_score]
      Rails.logger.info "#{Time.zone.now}: Creating new gene & data_array records from 10X CellRanger source data for #{study.name}"

      # now process all lines
      process_matrix_data(study, matrix_file, matrix_study_file)

      # create last batch of arrays
      create_data_arrays(@current_barcodes, matrix_study_file, 'cells', @current_gene, @data_arrays)
      create_data_arrays(@current_expression, matrix_study_file, 'expression', @current_gene, @data_arrays)

      # close file and clean up
      matrix_file.close

      # write last records to database
      Gene.create(@gene_documents)
      @count += @gene_documents.size
      Rails.logger.info "#{Time.zone.now}: Processed #{@count} expressed genes from 10X CellRanger source data for #{study.name}"
      DataArray.create(@data_arrays)
      @child_count += @data_arrays.size
      Rails.logger.info "#{Time.zone.now}: Processed #{@child_count} child data arrays from 10X CellRanger source data for #{study.name}"
      # create array of known cells for this expression matrix
      @barcodes.each_slice(DataArray::MAX_ENTRIES).with_index do |slice, index|
        Rails.logger.info "#{Time.zone.now}: Create known cells array ##{index + 1} for #{matrix_study_file.name}:#{matrix_study_file.id} in #{study.name}"
        known_cells = DataArray.new(study_id: study.id, name: "#{matrix_study_file.name} Cells", cluster_name: matrix_study_file.name,
                                    array_type: 'cells', array_index: index + 1, values: slice, study_file_id: matrix_study_file.id,
                                    linear_data_type: 'Study', linear_data_id: study.id)
        known_cells.save
      end

      # now we have to create empty gene records for all the non-significant genes
      # reset the count as we'll get an accurate total count from the length of the genes list
      @count = 0
      other_genes = []
      other_genes_count = 0
      @genes.each do |gene|
        if gene.is_a?(Array)
          gene_name, gene_id = gene
        else
          gene_name = gene
          gene_id = nil
        end
        other_genes << Gene.new(study_id: study.id, name: gene_name, searchable_name: gene_name.downcase, gene_id: gene_id, study_file_id: matrix_study_file.id).attributes
        other_genes_count += 1
        if other_genes.size % 1000 == 0
          Rails.logger.info "#{Time.zone.now}: creating #{other_genes_count} non-expressed gene records in #{study.name}"
          Gene.create(other_genes)
          @count += other_genes.size
          other_genes = []
        end
      end
      # process last batch
      Rails.logger.info "#{Time.zone.now}: creating #{other_genes_count} non-expressed gene records in #{study.name}"
      Gene.create(other_genes)
      @count += other_genes.size

      # finish up
      matrix_study_file.update(parse_status: 'parsed')
      genes_study_file.update(parse_status: 'parsed')
      barcodes_study_file.update(parse_status: 'parsed')

      # set gene count
      study.delay.set_gene_count

      # set the default expression label if the user supplied one
      if !study.has_expression_label? && !matrix_study_file.y_axis_label.blank?
        Rails.logger.info "#{Time.zone.now}: Setting default expression label in #{study.name} to '#{matrix_study_file.y_axis_label}'"
        study_opts = study.default_options
        study.update!(default_options: study_opts.merge(expression_label: matrix_study_file.y_axis_label))
      end

      # set initialized to true if possible
      if study.cluster_groups.any? && study.cell_metadata.any? && !study.initialized?
        Rails.logger.info "#{Time.zone.now}: initializing #{study.name}"
        study.update!(initialized: true)
        Rails.logger.info "#{Time.zone.now}: #{study.name} successfully initialized"
      end

      end_time = Time.zone.now
      time = (end_time - start_time).divmod 60.0
      @message = []
      @message << "#{Time.zone.now}: #{study.name} 10X CellRanger expression data parse completed!"
      @message << "Gene-level entries created: #{@count}"
      @message << "Total Time: #{time.first} minutes, #{time.last} seconds"
      Rails.logger.info @message.join("\n")
      begin
        SingleCellMailer.notify_user_parse_complete(user.email, "Gene-barcode matrix expression data has completed parsing", @message, study).deliver_now
      rescue => e
        ErrorTracker.report_exception(e, user, {message: @message})
        Rails.logger.error "#{Time.zone.now}: Unable to deliver email: #{e.message}"
      end

      # determine what to do with local files
      begin
        unless opts[:skip_upload] == true
          upload_or_remove_study_file(matrix_study_file, study)
          upload_or_remove_study_file(genes_study_file, study)
          upload_or_remove_study_file(barcodes_study_file, study)
        end
      rescue => e
        ErrorTracker.report_exception(e, user, {matrix_study_file: matrix_study_file.attributes.to_h,
                                                genes_study_file: genes_study_file.attributes.to_h,
                                                barcodes_study_file: barcodes_study_file.attributes.to_h,
                                                study: study.attributes.to_h})
        Rails.logger.error "Error in uploading files from sparse matrix parse to #{study.firecloud_project}/#{study.firecloud_workspace}#{study.bucket_id}: #{e.message}"
      end

      # finished, so return true
      true
    rescue => e
      ErrorTracker.report_exception(e, user, {matrix_study_file: matrix_study_file.attributes.to_h,
                                              genes_study_file: genes_study_file.attributes.to_h,
                                              barcodes_study_file: barcodes_study_file.attributes.to_h,
                                              study: study.attributes.to_h})
      error_message = e.message
      Rails.logger.error "#{Time.zone.now}: #{e.class.name}:#{error_message}, #{@last_line}"
      # error has occurred, so clean up records and remove file
      Gene.where(study_id: study.id, study_file_id: matrix_study_file.id).delete_all
      DataArray.where(study_id: study.id, study_file_id: matrix_study_file.id).delete_all
      # clean up files
      matrix_study_file.remove_local_copy
      genes_study_file.remove_local_copy
      barcodes_study_file.remove_local_copy
      unless opts[:sync] == true # if parse was initiated via sync, don't remove files
        delete_remote_file_on_fail(matrix_study_file, study)
        delete_remote_file_on_fail(genes_study_file, study)
        delete_remote_file_on_fail(barcodes_study_file, study)
      end
      bundle = matrix_study_file.study_file_bundle
      bundle.destroy
      matrix_study_file.destroy
      genes_study_file.destroy
      barcodes_study_file.destroy
      SingleCellMailer.notify_user_parse_fail(user.email, "Gene-barcode matrix expression data in #{study.name} parse has failed", error_message, study).deliver_now
      false
    end
  end

  # extract analysis output files based on a type of analysis output
  def self.extract_analysis_output_files(study, user, archive_file, analysis_method)
    begin
      study.make_data_dir
      Study.firecloud_client.execute_gcloud_method(:download_workspace_file, 0, study.bucket_id, archive_file.bucket_location,
                                                   study.data_store_path, verify: :none)
      Rails.logger.info "Successful localization of #{archive_file.upload_file_name}"
      archive_path = File.join(study.data_store_path, archive_file.download_location)
      extracted_files = []
      if archive_path.ends_with?('.zip')
        Zip::File.open(archive_path) do |zip_file|
          Dir.chdir(study.data_store_path)
          zip_file.each do |entry|
            unless entry.name.end_with?('/') || entry.name.start_with?('.')
              Rails.logger.info "Extracting: #{entry.name} in #{study.data_store_path}"
              entry.extract(entry.name)
              extracted_files << entry.name
            end
          end
        end
      elsif archive_path.ends_with?('tar.gz')
        archive_dir = File.join(study.data_store_path, archive_file.remote_location.split('/').first)
        Dir.chdir(archive_dir)
        # since there is a bug with tar extraction in RubyGems right now, we need to use the tar command from the OS
        system "tar -zxvf #{archive_path}"
        Rails.logger.info "Extraction of #{archive_path} complete"
        entries = Dir.entries(archive_dir).keep_if {|entry| entry.starts_with?('ideogram_exp_means') && entry.ends_with?('.json')}
        entries.each do |entry|
          extracted_files << File.join(archive_dir, entry)
        end
        Delayed::Job.enqueue(UploadCleanupJob.new(study, archive_file, 0), run_at: 2.minutes.from_now)
      else
        raise ArgumentError, "Unknown archive type: #{archive_path}; only .zip and .tar.gz archives are supported."
      end

      files_created = []
      case analysis_method
      when 'infercnv'
        # here we are extracting Ideogram.js JSON annotation files from a zipfile bundle and setting various
        # attributes to allow Ideogram to render this file with the correct cluster/annotation
        extracted_files.each do |file|
          converted_path = URI.unescape(file)
          file_basename = file.split('/').last
          Rails.logger.info "Opening #{converted_path} for new study_file creation"
          file_payload = File.open(converted_path)
          study_file = study.study_files.build(file_type: 'Analysis Output', name: file_basename.dup, upload: file_payload,
                                               status: 'uploaded', taxon_id: archive_file.taxon_id, genome_assembly_id: archive_file.genome_assembly_id)
          # chomp off filename header and .json at end
          file_basename.gsub!(/ideogram_exp_means__/, '')
          file_basename.gsub!(/\.json/, '')
          cluster_name, annotation_name, annotation_type, annotation_scope = file_basename.split('--')
          annotation_identifier = [annotation_name, annotation_type, annotation_scope].join('--')
          study_file.options = {
              analysis_name: analysis_method, visualization_name: 'ideogram.js',
              cluster_name: cluster_name, annotation_name: annotation_identifier,
              submission_id: archive_file.options[:submission_id]
          }
          study_file.description = "Ideogram.js annotation outputs for #{cluster_name}:#{annotation_name}"
          if study_file.save
            Rails.logger.info "Added #{study_file.name} as Ideogram Analysis Output to #{study.name}"
            files_created << study_file.name
            File.delete(file_payload.path) # remove temp copy
            run_at = 2.minutes.from_now
            begin
              Rails.logger.info "#{Time.zone.now}: preparing to upload Ideogram outputs: #{study_file.upload_file_name}:#{study_file.id} to FireCloud"
              study.send_to_firecloud(study_file)
              # clean up the extracted copy as we have a new copy in a subdir of the new study_file's ID
              Delayed::Job.enqueue(UploadCleanupJob.new(study, study_file, 0), run_at: run_at)
              Rails.logger.info "#{Time.zone.now}: cleanup job for #{study_file.upload_file_name}:#{study_file.id} scheduled for #{run_at}"
            rescue => e
              Rails.logger.info "#{Time.zone.now}: Ideogram output file: #{study_file.upload_file_name}:#{study_file.id} failed to upload to FireCloud due to #{e.message}"
              Delayed::Job.enqueue(UploadCleanupJob.new(study, study_file, 0), run_at: run_at)
            end
          else
            SingleCellMailer.notify_user_parse_fail(user.email, "Error: Zipfile extraction from inferCNV submission #{archive_file.options[:submission_id]} in #{study.name}", study_file.errors.full_messages.join(', '), study).deliver_now
          end
        end
        # email user that file extraction is complete
        message = ['The following files were extracted from the Ideogram zip archive and added to your study:']
        files_created.each {|file| message << file}
        SingleCellMailer.notify_user_parse_complete(user.email, "Zipfile extraction of inferCNV submission #{archive_file.options[:submission_id]} outputs has completed", message, study).deliver_now
      end
    rescue => e
      remove_extracted_archive_files(study, archive_file, extracted_files)
      SingleCellMailer.notify_user_parse_fail(user.email, "Error: Zipfile extraction from inferCNV submission #{archive_file.options[:submission_id]} in #{study.name} has failed", e.message, study).deliver_now
    end
  end

  private

  # read a single line of a coordinate matrix and return parsed indices and expression value
  def self.parse_line(line)
    raw_gene_idx, raw_barcode_idx, raw_expression_score = line.split.map(&:strip)
    gene_idx = raw_gene_idx.to_i - 1 # since arrays are zero based, we need to offset by 1
    barcode_idx = raw_barcode_idx.to_i - 1 # since arrays are zero based, we need to offset by 1
    expression_score = raw_expression_score.to_f.round(3) # only keep 3 significant digits
    [gene_idx, barcode_idx, expression_score]
  end

  # process a single line from a coordinate matrix and initialize a new gene object to use for associations
  # stores new values for barcodes and expression scores in containers to be converted into data_arrays later
  # returns current gene index and new gene object
  def self.initialize_new_gene(study, gene_idx, matrix_file)
    reference_gene = @genes[gene_idx]
    if reference_gene.is_a?(Array)
      gene_name, gene_id = reference_gene
    else
      gene_name = reference_gene
      gene_id = nil
    end
    new_gene = Gene.new(study_id: study.id, name: gene_name, searchable_name: gene_name.downcase, gene_id: gene_id, study_file_id: matrix_file.id)
    @gene_documents << new_gene.attributes
    [gene_idx, new_gene]
  end

  # main parser method, will iterate through lines and create documents as necessary
  def self.process_matrix_data(study, matrix_data, matrix_file)
    while !matrix_data.eof?
      line = matrix_data.readline.strip
      if line.strip.blank?
        break # would be the end of the file (hopefully)
      else
        gene_idx, barcode_idx, expression_score = parse_line(line)
        if @last_gene_index == gene_idx
          @current_barcodes << @barcodes[barcode_idx]
          @current_expression << expression_score
        else
          # we need to validate that the file is sorted correctly.  if our gene index has gone down from what it was before,
          # then we must abort and throw an error as the parse will not complete properly.  we will have all the genes,
          # but not all of the expression data
          if gene_idx < @last_gene_index
            Rails.logger.error "Error in parsing #{matrix_file.bucket_location} in #{study.name}: incorrect sort order; #{gene_idx + 1} is less than #{@last_gene_index + 1} at line #{matrix_data.lineno}"
            error_message = "Your input matrix is not sorted in the correct order.  The data must be sorted by gene index first, then barcode index: #{gene_idx + 1} is less than #{@last_gene_index + 1} at #{matrix_data.lineno}"
            raise StandardError, error_message
          end
          # create data_arrays and move to the next gene
          create_data_arrays(@current_barcodes, matrix_file, 'cells', @current_gene, @data_arrays)
          create_data_arrays(@current_expression, matrix_file, 'expression', @current_gene, @data_arrays)
          @last_gene_index, @current_gene = initialize_new_gene(study, gene_idx, matrix_file)
          @current_barcodes = [@barcodes[barcode_idx]]
          @current_expression = [expression_score]

          # batch insert records in groups of 1000
          if @data_arrays.size >= 1000
            Gene.create(@gene_documents) # genes must be saved first, otherwise the linear data polymorphic association is invalid and will cause a parse fail
            @count += @gene_documents.size
            Rails.logger.info "#{Time.zone.now}: Processed #{@count} expressed genes from 10X CellRanger source data for #{study.name}"
            @gene_documents = []
            DataArray.create(@data_arrays)
            @child_count += @data_arrays.size
            Rails.logger.info "#{Time.zone.now}: Processed #{@child_count} child data arrays from 10X CellRanger source data for #{study.name}"
            @data_arrays = []
          end
        end
      end
    end
  end

  # slice up arrays of barcodes and expression scores and create data arrays, storing them in a container for saving later
  def self.create_data_arrays(source_data, study_file, data_array_type, parent_gene, data_arrays_container)
    data_array_name = data_array_type == 'cells' ? parent_gene.cell_key : parent_gene.score_key
    source_data.each_slice(DataArray::MAX_ENTRIES).with_index do |slice, index|
      array = DataArray.new(name: data_array_name, cluster_name: study_file.name, array_type: data_array_type,
                                 array_index: index + 1, study_file_id: study_file.id, values: slice,
                                 linear_data_type: 'Gene', linear_data_id: parent_gene.id, study_id: parent_gene.study_id)
      data_arrays_container << array.attributes
    end
  end

  # localize a file for parsing and return opened file handler
  def self.localize_study_file(study_file, study)
    Rails.logger.info "#{Time.zone.now}: Attempting to localize #{study_file.upload_file_name}"
    if File.exists?(study_file.upload.path)
      local_path = study_file.upload.path
    elsif File.exists?(Rails.root.join(study.data_dir, study_file.download_location))
      local_path = File.join(study.data_store_path, study_file.download_location)
    else
      Rails.logger.info "Downloading #{study_file.upload_file_name} from remote"
      Study.firecloud_client.execute_gcloud_method(:download_workspace_file, 0, study.bucket_id, study_file.bucket_location,
                                                   study.data_store_path, verify: :none)
      Rails.logger.info "Successful localization of #{study_file.upload_file_name}"
      local_path = File.join(study.data_store_path, study_file.bucket_location)
    end
    content_type = study_file.determine_content_type
    if content_type == 'application/gzip'
      Rails.logger.info "#{Time.zone.now}: Parsing #{study_file.name}:#{study_file.id} as application/gzip"
      local_file = Zlib::GzipReader.open(local_path)
    else
      Rails.logger.info "#{Time.zone.now}: Parsing #{study_file.name}:#{study_file.id} as text/plain"
      local_file = File.open(local_path, 'rb')
    end
    local_file
  end

  # determine if local files need to be pushed to GCS bucket, or if they can be removed safely
  def self.upload_or_remove_study_file(study_file, study)
    Rails.logger.info "#{Time.zone.now}: determining upload status of #{study_file.file_type}: #{study_file.bucket_location}:#{study_file.id}"
    # now that parsing is complete, we can move file into storage bucket and delete local (unless we downloaded from FireCloud to begin with)
    # rather than relying on opts[:local], actually check if the file is already in the GCS bucket
    begin
      remote = Study.firecloud_client.execute_gcloud_method(:get_workspace_file, 0, study.bucket_id, study_file.bucket_location)
      if remote.nil?
        Rails.logger.info "#{Time.zone.now}: preparing to upload expression file: #{study_file.bucket_location}:#{study_file.id} to FireCloud"
        study.send_to_firecloud(study_file)
      else
        Rails.logger.info "#{Time.zone.now}: found remote version of #{study_file.bucket_location}: #{remote.name} (#{remote.generation})"
        run_at = 2.minutes.from_now
        Delayed::Job.enqueue(UploadCleanupJob.new(study, study_file, 0), run_at: run_at)
        Rails.logger.info "#{Time.zone.now}: cleanup job for #{study_file.bucket_location}:#{study_file.id} scheduled for #{run_at}"
      end
    rescue => e
      error_context = ErrorTracker.format_extra_context(study, study_file)
      ErrorTracker.report_exception(e, nil, error_context)
      Rails.logger.error "Error in pushing #{study_file.bucket_location}:#{study_file.id} to #{study.firecloud_project}/#{study.firecloud_workspace}:#{study.bucket_id}: #{e.message}"
      run_at = 2.minutes.from_now
      Delayed::Job.enqueue(UploadCleanupJob.new(study, study_file, 0), run_at: run_at)
      Rails.logger.info "UploadCleanupJob scheduled for #{run_at} for #{study_file.bucket_location}:#{study_file.id}"
    end
  end

  # delete a file from the bucket on fail
  def self.delete_remote_file_on_fail(study_file, study)
    remote = Study.firecloud_client.execute_gcloud_method(:get_workspace_file, 0, study.bucket_id, study_file.bucket_location)
    if remote.present?
      Study.firecloud_client.execute_gcloud_method(:delete_workspace_file, 0, study.bucket_id, study_file.bucket_location)
    end
  end

  # clean up any extracted files from a failed archive extraction job
  def self.remove_extracted_archive_files(study, archive, extracted_files)
    Rails.logger.error "Removing archive #{archive.upload_file_name} and #{extracted_files.size} extracted files from #{study.name}"
    extracted_files.each do |file|
      converted_filename = URI.unescape(file)
      file_basename = converted_filename.split('/').last
      match = StudyFile.find_by(study_id: study.id, upload_file_name: file_basename)
      if match.present?
        begin
          delete_remote_file_on_fail(match, study)
        rescue => e
          Rails.logger.error "Unable to remove remote copy of #{match.upload_file_name} from #{study.name}: #{e.message}"
        end
        match.destroy
      end
    end
    archive.remove_local_copy
    archive.destroy
  end
end
