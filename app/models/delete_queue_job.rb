class DeleteQueueJob < Struct.new(:object, :study_file_id)

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
      # set various attributes to hide study while it is queued for deletion
      # also free up name/workspace to be used again immediately
      # validate: false is used to prevent validations from blocking update
      object.assign_attributes(public: false, name: new_name, url_safe_name: new_name, firecloud_workspace: new_name)
      object.save(validate: false)
    when 'StudyFile'

      file_type = object.file_type
      study = object.study
      # remove all nested documents if present to avoid validation issues later
      # not all of them have validations but this guards against future errors in case they are added later
      # :nested_attributes returns all :accepts_nested_attributes_for documents in StudyFile as a Hash
      # e.g. { "expression_file_info_attributes"=>"expression_file_info_attributes=", ... }
      StudyFile.nested_attributes.keys.map { |key| key.chomp('_attributes') }.each do |nested_association|
        object.send(nested_association)&.destroy
      end

      # now remove all child objects first to free them up to be re-used.
      case file_type
      when 'Cluster'
        delete_differential_expression_results(study: study, study_file: object)
        delete_parsed_data(object.id, study.id, ClusterGroup, DataArray)
        delete_user_annotations(study:, study_file: object)
        reset_default_cluster(study:)
        reset_default_annotation(study:)
      when 'Coordinate Labels'
        delete_parsed_data(object.id, study.id, DataArray)
        remove_file_from_bundle
      when 'Expression Matrix'
        delete_parsed_data(object.id, study.id, Gene, DataArray)
        delete_differential_expression_results(study: study, study_file: object)
        study.set_gene_count
      when 'MM Coordinate Matrix'
        delete_differential_expression_results(study: study, study_file: object)
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
        delete_differential_expression_results(study: study, study_file: object)
        delete_parsed_data(object.id, study.id, CellMetadatum, DataArray)
        study.update(cell_count: 0)
        reset_default_annotation(study:)
      when 'AnnData'
        delete_convention_data(study: study, metadata_file: object)
        # delete user annotations first as we lose associations later
        delete_user_annotations(study:, study_file: object)
        delete_parsed_data(object.id, study.id, ClusterGroup, CellMetadatum, Gene, DataArray)
        delete_fragment_files(study:, study_file: object)
        # reset default options/counts
        study.reload
        study.cell_count = study.all_cells_array.size
        study.gene_count = study.unique_genes.size
        reset_default_cluster(study:)
        reset_default_annotation(study:)
        study.save
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

      # overwrite attributes to allow their immediate reuse
      # this must be done with a fresh StudyFile reference, otherwise upload_file_name may not overwrite
      new_name = "DELETE-#{SecureRandom.uuid}"
      file_reference = StudyFile.find(object.id)
      file_reference.update!(queued_for_deletion: true, upload_file_name: new_name, name: new_name, file_type: 'DELETE')

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
    when 'BSON::Document'
      study_file = StudyFile.find(study_file_id)
      delete_parsed_anndata_entries(study_file_id, study_file.study._id, object)
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

  # remove DE outputs when deleting study files
  # will remove corresponding outputs depending on file type
  def delete_differential_expression_results(study:, study_file:)
    case study_file.file_type
    when 'Metadata'
      results = DifferentialExpressionResult.where(study: study, annotation_scope: 'study')
    when 'Cluster'
      cluster = ClusterGroup.find_by(study: study, study_file: study_file)
      results = DifferentialExpressionResult.where(study: study, cluster_group: cluster)
    when 'Expression Matrix', 'MM Coordinate Matrix'
      results = DifferentialExpressionResult.where(study: study, matrix_file_id: study_file.id)
    end
    # extract results to Array to prevent open DB cursor from hanging and timing out as files are deleted in bucket
    results.to_a.each(&:destroy)
  end

  # remove UserAnnotation data from ClusterGroup
  def delete_user_annotations(study:, study_file:)
    # use ClusterGroup.where as AnnData files can have multiple ClusterGroup entries
    ClusterGroup.where(study:, study_file:).each do |cluster|
      user_annotations = UserAnnotation.where(study:, cluster_group_id: cluster.id)
      user_annotations.each do |annot|
        annot.user_data_arrays.delete_all
        annot.user_annotation_shares.delete_all
      end
      user_annotations.delete_all
    end
  end

  # handle unsetting default cluster for a study, if needed
  def reset_default_cluster(study:)
    if study.cluster_groups.by_name(study.default_options[:cluster]).nil?
      study.default_options[:cluster] = nil
      study.save
    end
  end

  # handle unsetting default_annotation for a study, if needed
  def reset_default_annotation(study:)
    current_default = study.default_annotation
    annot_name, annot_type, annot_scope = current_default&.split('--')
    case annot_scope
    when 'study'
      current_default = nil if study.cell_metadata.by_name_and_type(annot_name, annot_type).nil?
    when 'cluster'
      cluster = study.default_cluster
      annotation = cluster&.cell_annotations&.detect { |ca| ca[:name] == annot_name && ca[:type] == annot_type }
      current_default = nil if cluster.nil? || annotation.nil?
    else
      current_default = nil
    end
    if study.default_annotation != current_default
      study.default_options[:annotation] = current_default
      study.save
    end
  end

  # delete all AnnData "fragment" files upon study file deletion
  def delete_fragment_files(study:, study_file:)
    prefix = "_scp_internal/anndata_ingest/#{study_file.id}"
    remotes = ApplicationController.firecloud_client.get_workspace_files(study.bucket_id, prefix:)
    remotes.each(&:delete)
  end

  # to delete clustering data from parsed AnnData files
  # uses data_fragment entries to refine queries
  def delete_parsed_anndata_entries(study_file_id, study_id, fragment)
    safe_fragment = fragment.with_indifferent_access
    fragment_type = safe_fragment[:data_type]
    case fragment_type
    when "cluster"
      cluster_group = ClusterGroup.find_by(study_file_id:, study_id:, name: fragment[:name])

      data_arrays = DataArray.where(
        linear_data_type: 'ClusterGroup', linear_data_id: cluster_group.id, study_id:, study_file_id:
      )
      cluster_group.delete
      data_arrays.delete
    end
  end
end
