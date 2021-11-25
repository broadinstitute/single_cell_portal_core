require 'rubygems/package' # for tar reader
class ParseUtils

  # extract analysis output files based on a type of analysis output
  def self.extract_analysis_output_files(study, user, archive_file, analysis_method)
    begin
      study.make_data_dir
      ApplicationController.firecloud_client.execute_gcloud_method(:download_workspace_file, 0, study.bucket_id, archive_file.bucket_location,
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
          study_file.description = "Ideogram.js annotation outRails.logger.error for #{cluster_name}:#{annotation_name}"
          if study_file.save
            Rails.logger.info "Added #{study_file.name} as Ideogram Analysis Output to #{study.name}"
            files_created << study_file.name
            File.delete(file_payload.path) # remove temp copy
            run_at = 2.minutes.from_now
            begin
              Rails.logger.info "Preparing to upload Ideogram outRails.logger.error: #{study_file.upload_file_name}:#{study_file.id} to FireCloud"
              study.send_to_firecloud(study_file)
              # clean up the extracted copy as we have a new copy in a subdir of the new study_file's ID
              Delayed::Job.enqueue(UploadCleanupJob.new(study, study_file, 0), run_at: run_at)
              Rails.logger.info "Cleanup job for #{study_file.upload_file_name}:#{study_file.id} scheduled for #{run_at}"
            rescue => e
              Rails.logger.info "Ideogram output file: #{study_file.upload_file_name}:#{study_file.id} failed to upload to FireCloud due to #{e.message}"
              Delayed::Job.enqueue(UploadCleanupJob.new(study, study_file, 0), run_at: run_at)
            end
          else
            SingleCellMailer.notify_user_parse_fail(user.email, "Error: Zipfile extraction from inferCNV submission #{archive_file.options[:submission_id]} in #{study.name}", study_file.errors.full_messages.join(', '), study).deliver_now
          end
        end
        # email user that file extraction is complete
        message = ['The following files were extracted from the Ideogram zip archive and added to your study:']
        files_created.each {|file| message << file}
        SingleCellMailer.notify_user_parse_complete(user.email, "Zipfile extraction of inferCNV submission #{archive_file.options[:submission_id]} outRails.logger.error has completed", message, study).deliver_now
      end
    rescue => e
      remove_extracted_archive_files(study, archive_file, extracted_files)
      SingleCellMailer.notify_user_parse_fail(user.email, "Error: Zipfile extraction from inferCNV submission #{archive_file.options[:submission_id]} in #{study.name} has failed", e.message, study).deliver_now
    end
  end

  # parse a coordinate labels file and create necessary data_array objects
  # coordinate labels are specific to a cluster_group
  def self.initialize_coordinate_label_data_arrays(study, coordinate_file, user, opts={})
    begin
      @file_location = coordinate_file.local_location
      # before anything starts, check if file has been uploaded locally or needs to be pulled down from FireCloud first
      if !coordinate_file.is_local?
        # make sure data dir exists first
        study.make_data_dir
        ApplicationController.firecloud_client.execute_gcloud_method(:download_workspace_file, 0, study.bucket_id, coordinate_file.bucket_location,
                                                                     study.data_store_path, verify: :none)
        @file_location = File.join(study.data_store_path, coordinate_file.bucket_location)
      end

      # next, check if this is a re-parse job, in which case we need to remove all existing entries first
      if opts[:reparse]
        DataArray.where(study_id: study.id, study_file_id: coordinate_file.id).delete_all
        coordinate_file.invalidate_cache_by_file_type
      end

      # determine content type from file contents, not from upload_content_type
      content_type = coordinate_file.determine_content_type
      # validate headers
      if content_type == 'application/gzip'
        Rails.logger.info "Parsing #{coordinate_file.name}:#{coordinate_file.id} as application/gzip"
        c_file = Zlib::GzipReader.open(@file_location)
      else
        Rails.logger.info "Parsing #{coordinate_file.name}:#{coordinate_file.id} as text/plain"
        c_file = File.open(@file_location, 'rb')
      end

      # validate headers of coordinate file
      @validation_error = false
      @start_time = Time.zone.now
      headers = c_file.readline.split(/[\t,]/).map(&:strip)
      @last_line = "#{coordinate_file.name}, line 1"
      # must have at least NAME, X and Y fields
      unless (headers & %w(X Y LABELS)).size == 3
        coordinate_file.update(parse_status: 'failed')
        @validation_error = true
      end
      c_file.close
    rescue => e
      ErrorTracker.report_exception(e, user, study, coordinate_file, { opts: opts})
      coordinate_file.update(parse_status: 'failed')
      error_message = "#{e.message}"
      Rails.logger.error error_message
      filename = coordinate_file.upload_file_name
      coordinate_file.remove_local_copy
      coordinate_file.destroy
      SingleCellMailer.notify_user_parse_fail(user.email, "Error: Coordinate Labels file: '#{filename}' parse has failed", error_message, study).deliver_now
      raise StandardError, error_message
    end

    # raise validation error if needed
    if @validation_error
      error_message = "file header validation failed: should be at least NAME, X, Y, LABELS"
      Rails.logger.error error_message
      filename = coordinate_file.upload_file_name
      if File.exist?(@file_location)
        File.delete(@file_location)
        if Dir.exist?(File.join(study.data_store_path, coordinate_file.id))
          Dir.chdir(study.data_store_path)
          Dir.rmdir(coordinate_file.id)
        end
      end
      coordinate_file.destroy
      SingleCellMailer.notify_user_parse_fail(user.email, "Error: Coordinate Labels file: '#{filename}' parse has failed", error_message, study).deliver_now
      raise StandardError, error_message
    end

    # set up containers
    @labels_created = []
    @message = []
    begin
      # load target cluster
      cluster_file = coordinate_file.bundle_parent
      cluster = ClusterGroup.find_by(study_file_id: cluster_file.id, study_id: study.id)

      # check if ClusterGroup object is present before continuing, or if cluster file is still parsing
      # raise error if cluster file does not exist, or hasn't started parsing yet
      if cluster_file.nil? || cluster_file.parse_status == 'unparsed'
        raise StandardError.new('You must have uploaded a cluster file and associated it with this coordinate label file first before continuing.')
      elsif cluster_file.parsing? && cluster.nil?
        # if cluster file is parsing, re-run this job in 2 minutes
        Rails.logger.error "Aborting parse of #{coordinate_file.upload_file_name}:#{coordinate_file.id}; cluster file #{cluster_file.upload_file_name}:#{cluster_file.id} is still parsing"
        run_at = Rails.env.test? ? 30.seconds.from_now : 2.minutes.from_now
        ParseUtils.delay(run_at: run_at).initialize_coordinate_label_data_arrays(study, coordinate_file, user, opts)
        exit
      end

      Rails.logger.info "Beginning coordinate label initialization using #{coordinate_file.upload_file_name}:#{coordinate_file.id} for cluster: #{cluster.name} in #{study.name}"
      coordinate_file.update(parse_status: 'parsing')

      if content_type == 'application/gzip'
        coordinate_data = Zlib::GzipReader.open(@file_location)
      else
        coordinate_data = File.open(@file_location, 'rb')
      end

      raw_header_data = coordinate_data.readline.encode('UTF-8', invalid: :replace, undef: :replace, replace: '').split(/[\t,]/).map(&:strip)
      header_data = self.sanitize_input_array(raw_header_data)

      # determine if 3d coordinates have been provided
      is_3d = header_data.include?('Z')

      # grad header indices, z index will be nil if no 3d data
      x_index = header_data.index('X')
      y_index = header_data.index('Y')
      z_index = header_data.index('Z')
      label_index = header_data.index('LABELS')

      # container to store temporary data arrays until ready to save
      @data_arrays = []
      # create required data_arrays (name, x, y)
      @data_arrays[x_index] = cluster.data_arrays.build(name: 'x', cluster_name: cluster.name, array_type: 'labels',
                                                        array_index: 1, study_file_id: coordinate_file._id,
                                                        study_id: study.id, values: [])
      @data_arrays[y_index] = cluster.data_arrays.build(name: 'y', cluster_name: cluster.name, array_type: 'labels',
                                                        array_index: 1, study_file_id: coordinate_file._id,
                                                        study_id: study.id, values: [])
      @data_arrays[label_index] = cluster.data_arrays.build(name: 'text', cluster_name: cluster.name, array_type: 'labels',
                                                            array_index: 1, study_file_id: coordinate_file._id,
                                                            study_id: study.id, values: [])

      # add optional data arrays (z, metadata)
      if is_3d
        @data_arrays[z_index] = cluster.data_arrays.build(name: 'z', cluster_name: cluster.name, array_type: 'labels',
                                                          array_index: 1, study_file_id: coordinate_file._id, study_id: study.id,
                                                          values: [])
      end

      Rails.logger.info "Headers/Metadata loaded for coordinate file initialization using #{coordinate_file.upload_file_name}:#{coordinate_file.id} for cluster: #{cluster.name} in #{study.name}"
      # begin reading data
      while !coordinate_data.eof?
        line = coordinate_data.readline.strip.encode('UTF-8', invalid: :replace, undef: :replace, replace: '')
        if line.strip.blank?
          next
        else
          @last_line = "#{coordinate_file.name}, line #{coordinate_data.lineno}"
          raw_vals = line.split(/[\t,]/).map(&:strip)
          vals = self.sanitize_input_array(raw_vals)
          # assign value to corresponding data_array by column index
          vals.each_with_index do |val, index|
            if @data_arrays[index].values.size >= DataArray::MAX_ENTRIES
              # array already has max number of values, so save it and replace it with a new data array
              # of same name & type with array_index incremented by 1
              current_data_array_index = @data_arrays[index].array_index
              data_array = @data_arrays[index]
              Rails.logger.info "Saving full-length data array: #{data_array.name}-#{data_array.array_type}-#{data_array.array_index} using #{coordinate_file.upload_file_name}:#{coordinate_file.id} for cluster: #{cluster.name} in #{study.name}; initializing new array index #{current_data_array_index + 1}"
              data_array.save
              if data_array.array_type == 'labels'
                @labels_created << data_array
              end
              new_data_array = cluster.data_arrays.build(name: data_array.name, cluster_name: data_array.cluster_name,
                                                         array_type: data_array.array_type, array_index: current_data_array_index + 1,
                                                         study_file_id: coordinate_file._id, study_id: study.id, values: [])
              @data_arrays[index] = new_data_array
            end
            # determine whether or not value needs to be cast as a float or not (only values at label index stay as a string)
            if index == label_index
              @data_arrays[index].values << val
            else
              @data_arrays[index].values << val.to_f
            end
          end
        end

      end

      # clean up
      @data_arrays.each do |data_array|
        Rails.logger.info "Saving data array: #{data_array.name}-#{data_array.array_type}-#{data_array.array_index} using #{coordinate_file.upload_file_name}:#{coordinate_file.id} for cluster: #{cluster.name} in #{study.name}"
        data_array.save
      end
      coordinate_data.close
      coordinate_file.update(parse_status: 'parsed')
      @end_time = Time.zone.now
      self.log_to_mixpanel(study, coordinate_file, user, @start_time, @end_time, 'success')
      time = (@end_time - @start_time).divmod 60.0
      # assemble email message parts
      @message << "#{coordinate_file.upload_file_name} parse completed!"
      @message << "Labels created (#{@labels_created.size}: #{@labels_created.join(', ')}"
      @message << "Total Time: #{time.first} minutes, #{time.last} seconds"

      # expire cluster caches to load label data on render
      cluster_study_file = cluster.study_file
      cluster_study_file.invalidate_cache_by_file_type

      begin
        SingleCellMailer.notify_user_parse_complete(user.email, "Coordinate Label file: '#{coordinate_file.upload_file_name}' has completed parsing", @message, study).deliver_now
      rescue => e
        ErrorTracker.report_exception(e, user, study, coordinate_file, { opts: opts})
        Rails.logger.error "Unable to deliver email: #{e.message}"
      end

      Rails.logger.info "Determining upload status of coordinate labels file: #{coordinate_file.upload_file_name}:#{coordinate_file.id}"

      # now that parsing is complete, we can move file into storage bucket and delete local (unless we downloaded from FireCloud to begin with)
      destination = coordinate_file.bucket_location
      begin
        remote = ApplicationController.firecloud_client.execute_gcloud_method(:get_workspace_file, 0, study.bucket_id, destination)
      rescue => e
        ErrorTracker.report_exception(e, user, study, coordinate_file, { opts: opts})
        Rails.logger.error "Error retrieving remote: #{e.message}"
      end
      if remote.nil?
        begin
          Rails.logger.info "Preparing to upload coordinate label file: #{coordinate_file.upload_file_name}:#{coordinate_file.id} to FireCloud"
          study.send_to_firecloud(coordinate_file)
        rescue => e
          ErrorTracker.report_exception(e, user, study, coordinate_file, { opts: opts})
          Rails.logger.error "Coordinate label file: #{coordinate_file.upload_file_name}:#{coordinate_file.id} failed to upload to FireCloud due to #{e.message}"
          SingleCellMailer.notify_admin_upload_fail(coordinate_file, e.message).deliver_now
        end
      else
        # we have the file in FireCloud already, so just delete it
        begin
          Rails.logger.info "Found remote version of #{coordinate_file.upload_file_name}: #{remote.name} (#{remote.generation})"
          run_at = 15.seconds.from_now
          Delayed::Job.enqueue(UploadCleanupJob.new(study, coordinate_file, 0), run_at: run_at)
          Rails.logger.info "Cleanup job for #{coordinate_file.upload_file_name}:#{coordinate_file.id} scheduled for #{run_at}"
        rescue => e
          ErrorTracker.report_exception(e, user, study, coordinate_file, { opts: opts})
          # we don't really care if the delete fails, we can always manually remove it later as the file is in FireCloud already
          Rails.logger.error "Could not delete #{coordinate_file.name}:#{coordinate_file.id} in study #{study.name}; aborting"
          SingleCellMailer.admin_notification('Local file deletion failed', nil, "The file at #{@file_location} failed to clean up after parsing, please remove.").deliver_now
        end
      end
    rescue => e
      @end_time = Time.now
      ErrorTracker.report_exception(e, user, study, coordinate_file, { opts: opts})
      self.log_to_mixpanel(study, coordinate_file, user, @start_time, @end_time, 'failed')
      # error has occurred, so clean up records and remove file
      DataArray.where(study_file_id: coordinate_file.id).delete_all
      filename = coordinate_file.upload_file_name
      coordinate_file.remove_local_copy
      coordinate_file.destroy
      error_message = "#{@last_line} ERROR: #{e.message}"
      Rails.logger.error error_message
      SingleCellMailer.notify_user_parse_fail(user.email, "Error: Coordinate Labels file: '#{filename}' parse has failed", error_message, study).deliver_now
    end
  end

  # parse precomputed marker gene files and create documents to render in Morpheus
  def self.initialize_precomputed_scores(study, marker_file, user, opts={})
    begin
      @file_location = marker_file.upload.path
      # before anything starts, check if file has been uploaded locally or needs to be pulled down from FireCloud first
      if !marker_file.is_local?
        # make sure data dir exists first
        study.make_data_dir
        ApplicationController.firecloud_client.execute_gcloud_method(:download_workspace_file, 0, study.bucket_id, marker_file.bucket_location,
                                                                     study.data_store_path, verify: :none)
        @file_location = File.join(study.data_store_path, marker_file.bucket_location)
      end

      # next, check if this is a re-parse job, in which case we need to remove all existing entries first
      if opts[:reparse]
        study.precomputed_scores.where(study_file_id: marker_file.id).delete_all
        marker_file.invalidate_cache_by_file_type
      end

      @count = 0
      @message = []
      @start_time = Time.zone.now
      @last_line = ""
      @validation_error = false

      # determine content type from file contents, not from upload_content_type
      content_type = marker_file.determine_content_type
      # validate headers
      if content_type == 'application/gzip'
        Rails.logger.info "Parsing #{marker_file.name}:#{marker_file.id} as application/gzip"
        file = Zlib::GzipReader.open(@file_location)
      else
        Rails.logger.info "#Parsing #{marker_file.name}:#{marker_file.id} as text/plain"
        file = File.open(@file_location, 'rb')
      end

      # validate headers
      headers = file.readline.split(/[\t,]/).map(&:strip)
      @last_line = "#{marker_file.name}, line 1"
      if headers.first != 'GENE NAMES' || headers.size <= 1
        marker_file.update(parse_status: 'failed')
        @validation_error = true
      end
      file.close
    rescue => e
      ErrorTracker.report_exception(e, user, study, marker_file, { opts: opts})
      filename = marker_file.upload_file_name
      marker_file.remove_local_copy
      marker_file.destroy
      error_message = "#{@last_line} ERROR: #{e.message}"
      Rails.logger.info error_message
      SingleCellMailer.notify_user_parse_fail(user.email, "Error: Gene List file: '#{filename}' parse has failed", error_message, study).deliver_now
      # raise standard error to halt execution
      raise StandardError, error_message
    end

    # raise validation error if needed
    if @validation_error
      error_message = "file header validation failed: #{@last_line}: first header must be 'GENE NAMES' followed by clusters"
      filename = marker_file.upload_file_name
      marker_file.destroy
      Rails.logger.info error_message
      SingleCellMailer.notify_user_parse_fail(user.email, "Error: Gene List file: '#{filename}' parse has failed", error_message, study).deliver_now
      raise StandardError, error_message
    end

    # begin parse
    begin
      Rails.logger.info "Beginning precomputed score parse using #{marker_file.name}:#{marker_file.id} for #{study.name}"
      marker_file.update(parse_status: 'parsing')
      list_name = marker_file.name
      if list_name.nil? || list_name.blank?
        list_name = marker_file.upload_file_name.gsub(/(-|_)+/, ' ')
      end
      precomputed_score = study.precomputed_scores.build(name: list_name, study_file_id: marker_file._id)

      if content_type == 'application/gzip'
        marker_scores = Zlib::GzipReader.open(@file_location).readlines.map(&:strip).delete_if {|line| line.blank? }
      else
        marker_scores = File.open(@file_location, 'rb').readlines.map(&:strip).delete_if {|line| line.blank? }
      end

      raw_clusters = marker_scores.shift.split(/[\t,]/).map(&:strip)
      clusters = self.sanitize_input_array(raw_clusters, true)
      @last_line = "#{marker_file.name}, line 1"

      clusters.shift # remove 'Gene Name' at start
      precomputed_score.clusters = clusters
      rows = []
      # keep a running record of genes already parsed; same as expression_scores except precomputed_scores
      # have no built-in validations due to structure of gene_scores array
      @genes_parsed = []
      marker_scores.each_with_index do |line, i|
        @last_line = "#{marker_file.name}, line #{i + 2}"
        raw_vals = line.split(/[\t,]/).map(&:strip)
        vals = self.sanitize_input_array(raw_vals)
        gene = vals.shift.gsub(/\./, '_')
        if @genes_parsed.include?(gene)
          marker_file.update(parse_status: 'failed')
          user_error_message = "You have a duplicate gene entry (#{gene}) in your gene list.  Please check your file and try again."
          error_message = "Duplicate gene #{gene} in #{marker_file.name} (#{marker_file._id}) for study: #{study.name}"
          Rails.logger.info error_message
          raise StandardError, user_error_message
        else
          # gene is unique so far so add to list
          @genes_parsed << gene
        end

        row = {"#{gene}" => {}}
        clusters.each_with_index do |cluster, index|
          row[gene][cluster] = vals[index].to_f
        end
        rows << row
        @count += 1
      end
      precomputed_score.gene_scores = rows
      precomputed_score.save
      marker_file.update(parse_status: 'parsed')

      # assemble message
      @end_time = Time.zone.now
      self.log_to_mixpanel(study, marker_file, user, @start_time, @end_time, 'success')
      time = (@end_time - @start_time).divmod 60.0
      @message << "#{Time.zone.now}: #{marker_file.name} parse completed!"
      @message << "Total gene list entries created: #{@count}"
      @message << "Total Time: #{time.first} minutes, #{time.last} seconds"
      Rails.logger.info @message.join("\n")

      # send email
      begin
        SingleCellMailer.notify_user_parse_complete(user.email, "Gene list file: '#{marker_file.name}' has completed parsing", @message, study).deliver_now
      rescue => e
        ErrorTracker.report_exception(e, user, study, marker_file, { opts: opts})
        Rails.logger.error "Unable to deliver email: #{e.message}"
      end

      Rails.logger.info "Determining upload status of gene list file: #{marker_file.upload_file_name}"

      # now that parsing is complete, we can move file into storage bucket and delete local (unless we downloaded from FireCloud to begin with)
      destination = marker_file.bucket_location
      begin
        remote = ApplicationController.firecloud_client.execute_gcloud_method(:get_workspace_file, 0, study.bucket_id, destination)
      rescue => e
        ErrorTracker.report_exception(e, user, study, marker_file, { opts: opts})
        Rails.logger.error "Error retrieving remote: #{e.message}"
      end
      if remote.nil?
        begin
          Rails.logger.info "Preparing to upload gene list file: #{marker_file.upload_file_name}:#{marker_file.id} to FireCloud"
          study.send_to_firecloud(marker_file)
        rescue => e
          ErrorTracker.report_exception(e, user, study, marker_file, { opts: opts})
          Rails.logger.info "Gene List file: #{marker_file.upload_file_name}:#{marker_file.id} failed to upload to FireCloud due to #{e.message}"
          SingleCellMailer.notify_admin_upload_fail(marker_file, e.message).deliver_now
        end
      else
        # we have the file in FireCloud already, so just delete it
        begin
          Rails.logger.info "Found remote version of #{marker_file.upload_file_name}: #{remote.name} (#{remote.generation})"
          run_at = 15.seconds.from_now
          Delayed::Job.enqueue(UploadCleanupJob.new(study, marker_file, 0), run_at: run_at)
          Rails.logger.info "Cleanup job for #{marker_file.upload_file_name}:#{marker_file.id} scheduled for #{run_at}"
        rescue => e
          ErrorTracker.report_exception(e, user, study, marker_file, { opts: opts})
          # we don't really care if the delete fails, we can always manually remove it later as the file is in FireCloud already
          Rails.logger.error "Could not delete #{marker_file.name} in study #{study.name}; aborting"
          SingleCellMailer.admin_notification('Local file deletion failed', nil, "The file at #{@file_location} failed to clean up after parsing, please remove.").deliver_now
        end
      end
    rescue => e
      @end_time = Time.zone.now
      ErrorTracker.report_exception(e, user, study, marker_file, { opts: opts})
      self.log_to_mixpanel(study, marker_file, user, @start_time, @end_time, 'failed')
      # parse has failed, so clean up records and remove file
      PrecomputedScore.where(study_file_id: marker_file.id).delete_all
      filename = marker_file.upload_file_name
      marker_file.remove_local_copy
      marker_file.destroy
      error_message = "#{@last_line} ERROR: #{e.message}"
      Rails.logger.info error_message
      SingleCellMailer.notify_user_parse_fail(user.email, "Error: Gene List file: '#{filename}' parse has failed", error_message, study).deliver_now
    end
    true
  end

  # log parse job status to Mixpanel
  def self.log_to_mixpanel(study, study_file, user, start_time, end_time, status)
    total_runtime = (TimeDifference.between(start_time, end_time).in_seconds * 1000).to_i
    parser = caller_locations.first.base_label # will get the method name of caller, which will be the parse method
    job_props = {
      perfTime: total_runtime, # Latency in milliseconds
      fileType: study_file.file_type,
      fileSize: study_file.upload_file_size,
      action: parser,
      studyAccession: study.accession,
      jobStatus: status
    }
    MetricsService.log('rails-parse', job_props, user)
  end

  private

  # helper method to sanitize arrays of data for use as keys or names (removes quotes, can transform . into _)
  def self.sanitize_input_array(array, replace_periods=false)
    output = []
    array.each do |entry|
      value = entry.gsub(/(\"|\')/, '')
      output << (replace_periods ? value.gsub(/\./, '_') : value)
    end
    output
  end

  # delete a file from the bucket on fail
  def self.delete_remote_file_on_fail(study_file, study)
    remote = ApplicationController.firecloud_client.execute_gcloud_method(:get_workspace_file, 0, study.bucket_id, study_file.bucket_location)
    if remote.present?
      ApplicationController.firecloud_client.execute_gcloud_method(:delete_workspace_file, 0, study.bucket_id, study_file.bucket_location)
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
