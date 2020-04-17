

module Api
  module V1
    # contains helper methods for converting search results and studies to plain objects suitable
    # for returning as json
    # intended to be used as an include in controllers which use them, as they rely on instance variables
    module StudySearchResultsObjects
      def search_results_obj
        response_obj = {
          type: params[:type],
          terms: params[:terms],
          term_list: @term_list,
          current_page: @results.current_page.to_i,
          total_studies: @results.total_entries,
          total_pages: @results.total_pages,
          matching_accessions: @matching_accessions,
          preset_search: params[:preset_search]
        }
        if @selected_branding_group.present?
          response_obj[:scpbr] = @selected_branding_group.name_as_id
        end
        response_obj[:facets] = @facets.map { |facet| {id: facet[:id], filters: facet[:filters] } }
        response_obj[:studies] = @results.map { |study| study_response_obj(study) }
        response_obj
      end

      def study_response_obj(study)
        study_obj = {
          accession: study.accession,
          name: study.name,
          description: study.description,
          public: study.public,
          detached: study.detached,
          cell_count: study.cell_count,
          gene_count: study.gene_count,
          study_url: view_study_path(accession: study.accession, study_name: study.url_safe_name) +
                       (params[:scpbr].present? ? "?scpbr=#{params[:scpbr]}" : '')
        }
        if @studies_by_facet.present?
          # faceted search was run, so append filter matches
          study_obj[:facet_matches] = @studies_by_facet[study.accession]
        end
        if params[:terms].present?
          search_weight = study.search_weight(@term_list)
          study_obj[:term_matches] = search_weight[:terms].keys
          study_obj[:term_search_weight] = search_weight[:total]
        end
        # if this is an inferred match, use :term_matches for highlighting, but set :inferred_match to true
        if @inferred_accessions.present? && @inferred_accessions.include?(study.accession)
          study_obj[:inferred_match] = true
          inferred_weight = study.search_weight(@inferred_terms)
          study_obj[:term_matches] = inferred_weight[:terms].keys
          study_obj[:term_search_weight] = inferred_weight[:total]
        end
        if @preset_search.present? && @preset_search.accession_whitelist.include?(study.accession)
          study_obj[:preset_match] = true
        end
        if @gene_results.present?
          study_obj[:gene_matches] = @gene_results[:genes_by_study][study.id].uniq
          study_obj[:can_visualize_clusters] = study.can_visualize_clusters?
        end
        if study.detached
          study_obj[:study_files] = 'Unavailable (cannot load study workspace or bucket)'
        else
          study_obj[:study_files] = study_files_response_obj(study)
        end
        study_obj
      end

      def study_files_response_obj(study)
        file_objs = study.study_files.map { |study_file| study_file_response_obj(study_file) }
        files_by_category = {}
        StudyFile::BULK_DOWNLOAD_TYPES.each do |file_category|
          if file_category == 'Expression'
            files_by_category[:Expression] = file_objs.select do |file|
              ['Expression Matrix', 'MM Coordinate Matrix'].include?(file[:file_type])
            end
          else
            files_by_category[file_category] = file_objs.select do |file|
              file_category == file[:file_type]
            end
          end
        end
        files_by_category
      end

      def study_file_response_obj(study_file)
        study_file_obj = {
          name: study_file.name,
          file_type: study_file.file_type,
          description: study_file.description,
          bucket_location: study_file.bucket_location,
          upload_file_size: study_file.upload_file_size,
          download_url: api_v1_site_study_download_data_url(accession: study_file.study.accession, filename: study_file.bucket_location)
        }
        if study_file.is_bundle_parent?
          study_file_obj[:bundled_files] = study_file.bundled_files.map { |sf| study_file_response_obj(sf) }
        end
        study_file_obj
      end
    end
  end
end
