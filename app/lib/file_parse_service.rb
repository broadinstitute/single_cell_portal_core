# collection of methods involved in parsing files
# also includes option return status object when being called from Api::V1::StudyFilesController
class FileParseService
  # * *params*
  #   - +study_file+      (StudyFile) => File being parsed
  #   - +study+           (Study) => Study to which StudyFile belongs
  #   - +user+            (User) => User initiating parse action (for email delivery)
  #   - +reparse+         (Boolean) => Control for deleting existing data when initiating parse (default: false)
  #   - +persist_on_fail+ (Boolean) => Control for persisting files from GCS buckets on parse fail (default: false)
  #
  # * *returns*
  #   - (Hash) => Status object with http status_code and optional error message
  def self.run_parse_job(study_file, study, user, reparse: false, persist_on_fail: false)
    logger = Rails.logger
    logger.info "#{Time.zone.now}: Parsing #{study_file.name} as #{study_file.file_type} in study #{study.name}"
    if !study_file.parseable?
      return {
          status_code: 422,
          error: "Files of type #{study_file.file_type} are not parseable"
      }
    elsif study_file.parsing?
      return {
          status_code: 405,
          error: "File: #{study_file.upload_file_name} is already parsing"
      }
    else
      case study_file.file_type
      when 'Cluster'
        job = IngestJob.new(study: study, study_file: study_file, user: user, action: :ingest_cluster, reparse: reparse,
                            persist_on_fail: persist_on_fail)
        job.delay.push_remote_and_launch_ingest
      when 'Coordinate Labels'
        # we need to create the bundle here as it doesn't exist yet
        parent_cluster = ClusterGroup.find_by(id: study_file.options[:cluster_group_id])
        if parent_cluster.present?
          parent_cluster_file = parent_cluster.study_file
          file_list = StudyFileBundle.generate_file_list(parent_cluster_file, study_file)
          StudyFileBundle.find_or_create_by(study_id: study.id, bundle_type: parent_cluster_file.file_type,
                                            original_file_list: file_list)
          study.delay.initialize_coordinate_label_data_arrays(study_file, user, {reparse: reparse})
        else
          return self.missing_bundled_file(study_file)
        end
      when 'Expression Matrix'
        job = IngestJob.new(study: study, study_file: study_file, user: user, action: :ingest_expression, reparse: reparse,
                            persist_on_fail: persist_on_fail)
        job.delay.push_remote_and_launch_ingest
      when 'MM Coordinate Matrix'
        bundle = study_file.study_file_bundle
        barcodes = study_file.bundled_files.detect {|f| f.file_type == '10X Barcodes File'}
        genes = study_file.bundled_files.detect {|f| f.file_type == '10X Genes File'}
        if barcodes.present? && genes.present? && bundle.completed?
          genes.update(parse_status: 'parsing')
          barcodes.update(parse_status: 'parsing')
          job = IngestJob.new(study: study, study_file: study_file, user: user, action: :ingest_expression, reparse: reparse,
                              persist_on_fail: persist_on_fail)
          job.delay.push_remote_and_launch_ingest
        else
          study.delay.send_to_firecloud(study_file)
          return self.missing_bundled_file(study_file)
        end
      when '10X Genes File'
        # push immediately to avoid race condition when initiating parse
        study.delay.send_to_firecloud(study_file)
        bundle = study_file.study_file_bundle
        matrix = bundle.parent
        barcodes = bundle.bundled_files.detect {|f| f.file_type == '10X Barcodes File' }
        if barcodes.present? && matrix.present? && bundle.completed?
          matrix.update(parse_status: 'parsing')
          barcodes.update(parse_status: 'parsing')
          job = IngestJob.new(study: study, study_file: matrix, user: user, action: :ingest_expression, reparse: reparse,
                              persist_on_fail: persist_on_fail)
          job.delay.push_remote_and_launch_ingest(skip_push: true)
        else
          return self.missing_bundled_file(study_file)
        end
      when '10X Barcodes File'
        # push immediately to avoid race condition when initiating parse
        study.delay.send_to_firecloud(study_file)
        bundle = study_file.study_file_bundle
        matrix = bundle.parent
        genes = bundle.bundled_files.detect {|f| f.file_type == '10X Genes File' }
        if genes.present? && matrix.present? && bundle.completed?
          genes.update(parse_status: 'parsing')
          matrix.update(parse_status: 'parsing')
          job = IngestJob.new(study: study, study_file: matrix, user: user, action: :ingest_expression, reparse: reparse,
                              persist_on_fail: persist_on_fail)
          job.delay.push_remote_and_launch_ingest(skip_push: true)
        else
          return self.missing_bundled_file(study_file)
        end
      when 'Gene List'
        study.delay.initialize_precomputed_scores(study_file, user)
      when 'Metadata'
        job = IngestJob.new(study: study, study_file: study_file, user: user, action: :ingest_cell_metadata, reparse: reparse,
                            persist_on_fail: persist_on_fail)
        job.delay.push_remote_and_launch_ingest
      when 'Analysis Output'
        case @study_file.options[:analysis_name]
        when 'infercnv'
          if @study_file.options[:visualization_name] == 'ideogram.js'
            ParseUtils.delay.extract_analysis_output_files(@study, current_user, @study_file, @study_file.options[:analysis_name])
          end
        else
          Rails.logger.info "Aborting parse of #{@study_file.name} as #{@study_file.file_type} in study #{@study.name}; not applicable"
        end
      end
      study_file.update(parse_status: 'parsing')
      changes = ["Study file added: #{study_file.upload_file_name}"]
      if study.study_shares.any?
        SingleCellMailer.share_update_notification(study, changes, user).deliver_now
      end
      return {
          status_code: 204,
      }
    end
  end

  # Helper for rendering error when a bundled file is missing requirements for parsing
  def self.missing_bundled_file(study_file)
    Rails.logger.info "#{Time.zone.now}: Parse for #{study_file.name} as #{study_file.file_type} in study #{study_file.study.name} aborted; missing required files"
    {
        status_code: 412,
        error: "File is not parseable; missing required files for parsing #{study_file.file_type} file type: #{StudyFileBundle::PARSEABLE_BUNDLE_REQUIREMENTS.to_json}"
    }
  end
end
