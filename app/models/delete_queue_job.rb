class DeleteQueueJob < Struct.new(:object)

  ###
  #
  # DeleteQueueJob: generic class to queue objects for deletion.  Can handle studies, study files, user annotations,
  # and lists of files in a GCP bucket.
  #
  ###

  def perform
    # determine type of delete job
    case object.class.name
    when 'Study'
      # first check if we have convention metadata to delete
      if object.metadata_file.present?
        delete_convention_data(study: object, metadata_file: object.metadata_file)
      end
      # mark for deletion, rename study to free up old name for use, and restrict access by removing owner
      new_name = "DELETE-#{object.data_dir}"
      object.update!(public: false, name: new_name, url_safe_name: new_name)
    when 'StudyFile'
      file_type = object.file_type
      study = object.study

      # delete embedded expression_file_info to prevent validation errors later, if present
      object.expression_file_info.delete if object.expression_file_info.present?

      # now remove all child objects first to free them up to be re-used.
      case file_type
      when 'Cluster'
        if study.default_cluster.present? &&
            study.default_cluster.name == object.name
          study.default_options[:cluster] = nil
          study.default_options[:annotation] = nil
          study.save
        end
        cluster = ClusterGroup.find_by(study_file_id: object.id, study_id: study.id)
        delete_parsed_data(object.id, study.id, ClusterGroup)
        delete_parsed_data(object.id, study.id, DataArray)
        if cluster.present?
          user_annotations = UserAnnotation.where(study_id: study.id, cluster_group_id: cluster.id )
          user_annotations.each do |annot|
            annot.user_data_arrays.delete_all
            annot.user_annotation_shares.delete_all
          end
          user_annotations.delete_all
        end
      when 'Coordinate Labels'
        delete_parsed_data(object.id, study.id, DataArray)
        remove_file_from_bundle
      when 'Expression Matrix'
        delete_parsed_data(object.id, study.id, Gene, DataArray)
        study.set_gene_count
      when 'MM Coordinate Matrix'
        delete_parsed_data(object.id, study.id, Gene, DataArray)
        study.set_gene_count
      when /10X/
        bundle = object.study_file_bundle
        if bundle.present?
          if bundle.study_files.any?
            object.study_file_bundle.study_files.each do |file|
              file.update(parse_status: 'unparsed')
            end
          end
          parent = object.study_file_bundle.parent
          if parent.present?
            delete_parsed_data(parent.id, study.id, Gene, DataArray)
          end
        end
        remove_file_from_bundle
      when 'Metadata'
        delete_convention_data(study: study, metadata_file: object)

        # clean up all subsampled data, as it is now invalid and will be regenerated
        # once a user adds another metadata file
        ClusterGroup.where(study_id: study.id).each do |cluster_group|
          delete_subsampled_data(cluster_group)
        end

        delete_parsed_data(object.id, study.id, CellMetadatum, DataArray)
        study.update(cell_count: 0)
        # unset default annotation if it was study-based
        if study.default_options[:annotation].present? &&
            study.default_options[:annotation].end_with?('--study')
          study.default_options[:annotation] = nil
          study.save
        end
      when 'Gene List'
        delete_parsed_data(object.id, study.id, PrecomputedScore)
      when 'BAM Index'
        remove_file_from_bundle
      else
        nil
      end

      # if this is a parent bundled file, delete all other associated files and bundle
      if object.is_bundle_parent?
        object.bundled_files.each do |file|
          Rails.logger.info "Deleting bundled file #{file.upload_file_name} from #{study.name} due to parent deletion: #{object.upload_file_name}"
          DeleteQueueJob.new(file).perform
        end
        object.study_file_bundle.destroy
      end

      # it is safe to call :destroy now as all child documents have been removed
      object.destroy

      # reset initialized if needed
      if study.cluster_groups.empty? || study.genes.empty? || study.cell_metadata.empty?
        study.update(initialized: false)
      end
    when 'UserAnnotation'
      study = object.study
      # unset default annotation if it was this user_annotation
      if study.default_annotation == object.formatted_annotation_identifier
        study.default_options[:annotation] = nil
        study.save
      end
      # set queued for deletion to true and set user annotation name
      new_name = "DELETE-#{SecureRandom.uuid}"
      object.update!(name: new_name)

      # delete data arrays and shares right away
      object.user_data_arrays.delete_all
      object.user_annotation_shares.delete_all
    when 'Google::Cloud::Storage::File::List'
      # called when a user wants to delete an entire directory of files from a FireCloud submission
      # this is run in the foreground as Delayed::Job cannot deserialize the list anymore
      files = object
      files.each {|f| f.delete}
      while files.next?
        files = object.next
        files.each {|f| f.delete}
      end
    end
  end

  private

  # remove a study_file from a study_file_bundle, and clean original_file_list up as necessary
  def remove_file_from_bundle
    bundle = object.study_file_bundle
    if bundle.present?
      bundle.original_file_list.delete_if {|file| file['file_type'] == object.file_type} # this edits the list in place, but is not saved
      object.update(study_file_bundle_id: nil)
      bundle.save
    end
  end

  # removed all parsed data from provided list of models
  def delete_parsed_data(object_id, study_id, *models)
    models.each do |model|
      model.where(study_file_id: object_id, study_id: study_id).delete_all
    end
  end

  # remove all subsampling data when a user deletes a metadata file, as adding a new metadata file will cause all
  # subsamples to be regenerated
  def delete_subsampled_data(cluster)
    cluster.find_subsampled_data_arrays.delete_all
    cluster.update(subsampled: false)
  end

  # delete convention data from BQ if a user deletes a convention metadata file, or a study that contains convention data
  def delete_convention_data(study:, metadata_file:)
    bq_dataset = ApplicationController.big_query_client.dataset CellMetadatum::BIGQUERY_DATASET
    if metadata_file.use_metadata_convention
      bq_dataset.query "DELETE FROM #{CellMetadatum::BIGQUERY_TABLE} WHERE study_accession = '#{study.accession}' AND file_id = '#{metadata_file.id}'"
      SearchFacet.delay.update_all_facet_filters
    end
  end
end
