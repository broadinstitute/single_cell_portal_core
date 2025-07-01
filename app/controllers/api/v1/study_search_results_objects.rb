module Api
  module V1
    # contains helper methods for converting search results and studies to plain objects suitable
    # for returning as json
    # intended to be used as an include in controllers which use them, as they rely on instance variables
    module StudySearchResultsObjects

      # list of metadata names to include in cohort responses
      COHORT_METADATA = %w[disease__ontology_label organ__ontology_label species__ontology_label sex
                           library_preparation_protocol__ontology_label].freeze
      # headers for TSV text export of search results
      TEXT_HEADERS = [
        'Study source', 'Accession', 'Name', 'Description', 'Public', 'Detached', 'Cell count', 'Gene count',
        'Study URL', 'Disease', 'Organ', 'Species', 'Sex', 'Library preparation protocol', 'Facet matches',
        'Term matches'
      ].freeze
      COMMA_SPACE = ', '.freeze

      def search_results_obj
        response_obj = {
          type: @search_type,
          terms: params[:terms],
          term_list: @term_list,
          current_page: @results.current_page.to_i,
          total_studies: @results.total_entries,
          total_pages: @results.total_pages,
          matching_accessions: @matching_accessions,
          preset_search: params[:preset_search],
          match_by_data: @match_by_data
        }
        if @selected_branding_group.present?
          response_obj[:scpbr] = @selected_branding_group.name_as_id
        end
        response_obj[:facets] = @facets.map { |facet| {id: facet[:id], filters: facet[:filters] } }
        response_obj[:studies] = @results.map { |study| study_response_obj(study) }
        response_obj
      end

      def study_response_obj(study)
        if study.is_a?(Study)
          study_obj = {
            study_source: 'SCP',
            accession: study.accession,
            name: study.name,
            description: study.description,
            public: study.public,
            detached: study.detached,
            cell_count: study.cell_count,
            gene_count: study.gene_count,
            study_url: view_study_path(accession: study.accession, study_name: study.url_safe_name) +
              (params[:scpbr].present? ? "?scpbr=#{params[:scpbr]}" : ''),
            metadata: cohort_metadata(study)
          }
          if @studies_by_facet.present? && @studies_by_facet[study.accession].present?
            # faceted search was run, so append filter matches after merging
            merged_data = Api::V1::StudySearchResultsObjects.merge_facet_matches(study_obj[:facet_matches],
                                                                                 @studies_by_facet[study.accession])
            study_obj[:facet_matches] = merged_data
          end
          if params[:terms].present?
            search_weight = study.search_weight(@term_list)
            study_obj[:term_matches] = search_weight[:terms].keys
            study_obj[:term_search_weight] = search_weight[:total]
            # also incorporate converted terms => facets for badges
            if @metadata_matches.present? && @metadata_matches[study.accession].present?
              merged_data = Api::V1::StudySearchResultsObjects.merge_facet_matches(study_obj[:facet_matches],
                                                                                   @metadata_matches[study.accession])
              study_obj[:facet_matches] = merged_data
            end
          end
          # if this is an inferred match, use :term_matches for highlighting, but set :inferred_match to true
          if @inferred_accessions.present? && @inferred_accessions.include?(study.accession)
            study_obj[:inferred_match] = true
            inferred_weight = study.search_weight(@inferred_terms)
            study_obj[:term_matches] = inferred_weight[:terms].keys
            study_obj[:term_search_weight] = inferred_weight[:total]
          end
          if @preset_search.present? && @preset_search.accession_list.include?(study.accession)
            study_obj[:preset_match] = true
          end
          if @gene_results.present? && @gene_results[:genes_by_study].any?
            study_obj[:gene_matches] = @gene_results[:genes_by_study][study.id].uniq
            study_obj[:can_visualize_clusters] = study.can_visualize_clusters?
            study_obj[:default_annotation_id] = study.default_annotation
            study_obj[:annotation_list] = AnnotationVizService.get_study_annotation_options(study, current_api_user)
          end
        else
          study_obj = {
            study_source: study[:hca_result] ? 'HCA' : 'TDR',
            accession: study[:accession],
            name: study[:name],
            description: study[:description],
            public: true,
            detached: false,
            hca_project_id: study[:hca_project_id],
            cell_count: 0,
            gene_count: 0,
            metadata: study[:metadata],
            study_url: '#',
            file_information: study[:file_information],
            term_matches: study[:term_matches],
            term_search_weight: study[:term_search_weight]
          }
          if @studies_by_facet.present?
            # faceted search was run, so append filter matches
            study_obj[:facet_matches] = @studies_by_facet[study[:accession]]
          end
        end
        study_obj
      end

      def cohort_metadata(study)
        cohort_entries = {}
        COHORT_METADATA.each do |name|
          metadatum = study.cell_metadata.by_name_and_type(name, 'group')
          display_name = name.chomp('__ontology_label').to_sym
          cohort_entries[display_name] = metadatum&.values&.sort || []
        end
        cohort_entries
      end

      def results_text_export
        lines = [TEXT_HEADERS.join("\t")]
        @studies.each { |study| lines << study_text_export(study).join("\t") }
        lines.join("\n")
      end

      def study_text_export(study)
        if study.is_a?(Study)
          metadata = cohort_metadata(study).with_indifferent_access
          term_matches = study.search_weight(@term_list || [])
          facet_data = @studies_by_facet&.[](study.accession) || {}
          text_to_facet = @metadata_matches&.[](study.accession) || {}
          facet_matches = Api::V1::StudySearchResultsObjects.merge_facet_matches(facet_data, text_to_facet)
          [
            'SCP',
            study.accession,
            study.name,
            study.description,
            study.public,
            study.detached,
            study.cell_count,
            study.gene_count,
            result_url_for(study),
            metadata[:disease].join(COMMA_SPACE),
            metadata[:organ].join(COMMA_SPACE),
            metadata[:species].join(COMMA_SPACE),
            metadata[:sex].join(COMMA_SPACE),
            metadata[:library_preparation_protocol].join(COMMA_SPACE),
            Api::V1::StudySearchResultsObjects.facet_results_as_text(facet_matches),
            term_matches[:terms].keys.join(COMMA_SPACE)
          ]
        else
          [
            study[:hca_result] ? 'HCA' : 'TDR',
            study[:accession],
            study[:name],
            study[:description].gsub(/\n/, ''),
            true,
            false,
            0,
            0,
            result_url_for(study),
            study.dig(:metadata, :disease).join(COMMA_SPACE),
            study.dig(:metadata, :organ).join(COMMA_SPACE),
            study.dig(:metadata, :species).join(COMMA_SPACE),
            study.dig(:metadata, :sex).join(COMMA_SPACE),
            study.dig(:metadata, :library_preparation_protocol).join(COMMA_SPACE),
            Api::V1::StudySearchResultsObjects.facet_results_as_text(@studies_by_facet[study[:accession]]),
            nil
          ]
        end
      end

      # returns a URL for the study, either SCP or HCA
      def result_url_for(study)
        if study.is_a?(Study)
          view_study_url(accession: study.accession, study_name: study.url_safe_name)
        else
          "https://data.humancellatlas.org/explore/projects/#{study[:hca_project_id]}"
        end
      end

      # flatten facet matches into a text string for export
      def self.facet_results_as_text(facets)
        entries = []
        facets.delete(:facet_search_weight)
        facets.each do |facet_name, filters|
          entries << "#{facet_name}:#{filters.map { |f| f[:name] }.join('|')}"
        end
        entries.join(COMMA_SPACE)
      end

      # merge in multiple facet match data objects into a single merged entity for a given study
      def self.merge_facet_matches(existing_data, new_data)
        study_data = existing_data || {}
        merged_match_data = {}
        all_keys = (study_data.keys + new_data.keys).uniq
        all_keys.each do |facet_name|
          next if facet_name.to_s == 'facet_search_weight'

          merged_match_data[facet_name] ||= []
          merged_match_data[facet_name] += study_data[facet_name] if study_data[facet_name].present?
          merged_match_data[facet_name] += new_data[facet_name] if new_data[facet_name].present?
          merged_match_data[facet_name].uniq! { |filter| filter[:name] }
        end
        merged_match_data[:facet_search_weight] = merged_match_data.values.flatten.size
        merged_match_data
      end
    end
  end
end
