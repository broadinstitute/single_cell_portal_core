module Api
  module V1
    class SearchController < ApiBaseController
      include StudySearchResultsObjects

      # regex to match on 'sequence_file' and 'analysis_file' entries from TDR
      TDR_FILE_OUTPUT_TYPE_MATCH = /_file/.freeze

      # value used to separate facet entries in query string params
      FACET_DELIMITER = ';'.freeze
      # value used to separate filter values for a facet in query string params
      FILTER_DELIMITER = '|'.freeze

      before_action :set_current_api_user!
      before_action :authenticate_api_user!, only: [:create_auth_code]
      before_action :set_search_facet, only: :facet_filters
      before_action :set_search_facets_and_filters, only: :index
      before_action :set_preset_search, only: :index
      before_action :set_branding_group, only: [:index, :facets]

      swagger_path '/search' do
        operation :get do
          key :tags, [
              'Search'
          ]
          key :summary, 'Faceted & keyword search for studies & cells'
          key :description, 'Search studies or cells using facets and keywords.'
          key :operationId, 'search_studies'
          parameter do
            key :name, :type
            key :in, :query
            key :description, 'Type of query to perform (study- or cell-based)'
            key :required, true
            key :type, :string
            key :enum, ['study', 'cell']
          end
          parameter do
            key :name, :facets
            key :in, :query
            key :description, 'User-supplied list facets and filters.  Delimit facets from filters with ":", filter ' \
                              "values with '#{FILTER_DELIMITER}' and facet entries with '#{FACET_DELIMITER}'"
            key :example, "facet_id:filter_value#{FACET_DELIMITER}facet_id_2:filter_value_2#{FILTER_DELIMITER}filter_value_3"
            key :required, false
            key :type, :string
          end
          parameter do
            key :name, :terms
            key :in, :query
            key :description, 'User-supplied query string'
            key :required, false
            key :type, :string
          end
          parameter do
            key :name, :genes
            key :in, :query
            key :description, 'space-delimited list of genes.  e.g. "agpat2 farsa"'
            key :required, false
            key :type, :string
          end
          parameter do
            key :name, :preset_search
            key :in, :query
            key :description, 'Identifier of preset/stored query'
            key :required, false
            key :type, :string
          end
          parameter do
            key :name, :external
            key :in, :query
            key :description, 'External search services to query in addition to SCP'
            key :required, false
            key :type, :string
            key :enum, %w[hca]
          end
          parameter do
            key :name, :page
            key :in, :query
            key :description, 'Page number for pagination control'
            key :required, false
            key :type, :integer
          end
          parameter do
            key :name, :scpbr
            key :in, :query
            key :description, 'Requested branding group (to filter results on)'
            key :reqired, false
            key :type, :string
          end
          parameter do
            key :name, :order
            key :in, :query
            key :description, 'Requested order of results'
            key :reqired, false
            key :type, :string
            key :enum, [:recent, :popular]
          end
          response 200 do
            key :description, 'Search parameters, Studies and StudyFiles'
            schema do
              key :title, 'Search Results'
              property :type do
                key :type, :string
                key :description, 'Type of search performed'
              end
              property :terms do
                key :type, :string
                key :title, 'Keywords used in search'
              end
              property :current_page do
                key :type, :integer
                key :title, 'Current page of paginated studies'
              end
              property :total_pages do
                key :type, :integer
                key :title, 'Total number of pages of studies'
              end
              property :total_studies do
                key :type, :integer
                key :title, 'Total number of studies matching search'
              end
              property :scpbr do
                key :type, :string
                key :description, 'Requested branding group id'
              end
              property :matching_accessions do
                key :type, :array
                key :description, 'Array of study accessions matching query'
                items do
                  key :type, :string
                end
              end
              property :facets do
                key :type, :array
                key :title, 'SearchFacets'
                key :description, 'Array of facets/filters used in search'
                items do
                  key :type, :object
                  key :title, 'SearchFacet'
                  property :id do
                    key :type, :string
                    key :description, 'ID of facet'
                  end
                  property :filters do
                    key :type, :array
                    key :description, 'Matching filters'
                    items do
                      key :type, :object
                      key :title, 'Filter'
                      property :name do
                        key :type, :string
                        key :description, 'Display value of filter'
                      end
                      property :id do
                        key :type, :string
                        key :description, 'ID value of filter'
                      end
                    end
                  end
                end
              end
              property :studies do
                key :type, :array
                items do
                  key :title, 'Study, StudyFiles'
                  key :'$ref', :SearchStudyWithFiles
                end
              end
            end
          end
          response 406 do
            key :description, ApiBaseController.not_acceptable
          end
          response 500 do
            key :description, 'Server error'
          end
        end
      end

      def index
        @viewable = Study.viewable(current_api_user)
        @search_type = params[:type]&.to_sym || :study # handle empty type

        # filter results by branding group, if specified
        if @selected_branding_group.present?
          @viewable = @viewable.where(:branding_group_ids.in => [@selected_branding_group.id])
        end
        # variable for determining how we will sort search results for relevance
        sort_type = :none

        # if a user requested a preset search, override search parameters to load the requested query
        if @preset_search.present?
          params[:terms] = "#{@preset_search.keyword_query_string} #{params[:terms]}".strip
          @facets = @preset_search.matching_facets_and_filters if @preset_search.search_facets.any?
          # if accession list is provided, scope viewable to only those studies
          if @preset_search.accession_list.any?
            sort_type = :accession_list if params[:terms].blank?
            @accession_list = @preset_search.accession_list
            logger.info "Scoping search results to accessions from preset search: #{@preset_search.name}: #{@accession_list}"
            @viewable = @viewable.where(:accession.in => @accession_list)
          end
        end

        # if search params are present, filter accordingly
        if params[:terms].present?
          sort_type = :keyword
          @search_terms = RequestUtils.sanitize_search_terms params[:terms]
          # determine if search values contain possible study accessions
          possible_accessions = StudyAccession.sanitize_accessions(@search_terms.split)
          # determine query case based off of search terms (either :keyword or :phrase)
          if @search_terms.include?('"')
            @term_list = self.class.extract_phrases_from_search(query_string: @search_terms)
            logger.info "Performing phrase-based search using #{@term_list}"
            search_match_obj = ::StudySearchService.generate_mongo_query_by_context(terms: @term_list,
                                                                                    base_studies: @viewable,
                                                                                    accessions: possible_accessions,
                                                                                    query_context: :phrase)
            @studies = search_match_obj[:studies]
            @match_by_data = search_match_obj[:results_matched_by_data]
            @metadata_matches = search_match_obj[:metadata_matches]
            logger.info "Found #{@studies.count} studies in phrase search: #{@studies.pluck(:accession)}"
          else
            # filter & reconstitute query w/o stop words
            @term_list = self.class.reject_stop_words_from_terms(@search_terms.split)
            sanitized_terms = @term_list.join(' ')
            logger.info "Performing keyword-based search using #{@term_list}"
            search_match_obj = ::StudySearchService.generate_mongo_query_by_context(terms: sanitized_terms,
                                                                                    base_studies: @viewable,
                                                                                    accessions: possible_accessions,
                                                                                    query_context: :keyword)

            @studies = search_match_obj[:studies]
            @match_by_data = search_match_obj[:results_matched_by_data]
            @metadata_matches = search_match_obj[:metadata_matches]
            logger.info "Found #{@studies.count} studies in keyword search: #{@studies.pluck(:accession)}"
          end
          # all of our terms were accessions, so this is a "cached" query, and we want to return
          # results in the exact order specified in the accessions array
          if possible_accessions.size == @term_list.size
            sort_type = :accession
          end
        else
          @studies = @viewable
        end

        # only call BigQuery if list of possible studies is larger than 0 and we have matching facets to use
        if @studies.count > 0 && @facets.any?
          sort_type = :facet
          @studies_by_facet = {}
          query_results = StudySearchService.perform_mongo_facet_search(@facets)
          # build up map of study matches by facet & filter value (for adding labels in UI)
          @studies_by_facet = self.class.match_studies_by_facet(query_results, @facets)
          # uniquify result list as one study may match multiple facets/filters
          @convention_accessions = query_results.map { |match| match[:study_accession] }.uniq
          # report on matches for metadata, ensuring we don't double-count some accessions
          # this can happen if we get a term conversion to metadata match
          @match_by_data ||= {}
          existing_metadata_matches = @metadata_matches.try(:keys) || []
          total_metadata_matches = (existing_metadata_matches + @convention_accessions).uniq
          existing_total_matches = @match_by_data['numResults:scp'].to_i
          @match_by_data['numResults:scp:metadata'] = total_metadata_matches.size
          @match_by_data['numResults:scp'] = existing_total_matches + total_metadata_matches.size
          logger.info "Found #{@convention_accessions.count} matching studies from query: #{@convention_accessions}"
          @studies = @studies.where(:accession.in => @convention_accessions)
        end

        # filter the studies by genes if asked
        if params[:genes].present?
          @gene_results = ::StudySearchService.find_studies_by_gene_param(params[:genes], @studies.pluck(:id))
          @studies = @studies.where(:id.in => @gene_results[:study_ids])
        end

        # reset order if user requested a custom ordering
        if params[:order].present?
          sort_type = params[:order].to_sym
        end

        # convert to array to allow appending external search results (Azul, TDR, etc.)
        @studies = @studies.to_a

        # perform Azul search if there are facets/terms provided by user, and they requested HCA results
        # run this before inferred search so that they are weighted and sorted correctly
        # skip if user is searching inside a collection or they are performing global gene search
        include_azul = params[:external] == 'hca' && @search_type == :study && @selected_branding_group.nil?
        if (@facets.present? || @term_list.present?) && include_azul
          begin
            azul_results = ::AzulSearchService.append_results_to_studies(@studies,
                                                                         selected_facets: @facets,
                                                                         terms: @term_list,
                                                                         facet_map: @studies_by_facet,
                                                                         results_matched_by_data: @match_by_data)
            @studies = azul_results[:studies]
            @studies_by_facet = azul_results[:facet_map]
            @matches_by_data = azul_results[:results_matched_by_data]
            # @studies, @studies_by_facet = ::TdrSearchService.append_results_to_studies(@studies,
            #                                                                             selected_facets: @facets,
            #                                                                             terms: @term_list,
            #                                                                             facet_map: @studies_by_facet)
          rescue RestClient::Exception => e
            logger.error "Error in retrieving results from Azul - #{e.class}: #{e.message}"
            ErrorTracker.report_exception(e, current_api_user,
                                          { facets: @facets }, { terms: @term_list })
          end
        end

        # determine sort order for pagination; minus sign (-) means a descending search
        case sort_type
        when :keyword
          @studies = @studies.sort_by do |study|
            if study.is_a? Study
              # combine text hits with metadata match totals to get real weight
              metadata_weight = @metadata_matches&.dig(study.accession, :facet_search_weight).to_i || 0
              [-(study.search_weight(@term_list)[:total] + metadata_weight), 0]
            else
              [-study[:term_search_weight], 1] # external studies are always weighted lower
            end
          end
        when :accession
          @studies = @studies.sort_by do |study|
            accession_index = possible_accessions.index(study.accession)
            if accession_index.nil?
              # study was not a true accession match, it matches the accession term in its description
              # make this appear after the proper accession matches, in order of weight match
              accession_index = 9999 - study.search_weight(@term_list)[:total]
            end
            accession_index
          end
        when :accession_list
          @studies = @studies.sort_by { |study| @accession_list.index(study.accession) }
        when :facet
          @studies = @studies.sort_by do |study|
            accession = self.class.get_study_attribute(study, :accession)
            metadata_weight = @metadata_matches&.dig(accession, :facet_search_weight)&.to_i || 0
            [
              -(@studies_by_facet[accession][:facet_search_weight] + metadata_weight), # sort by facet weight
              study.is_a?(Study) ? 0 : 1 # prioritize SCP results over external
            ]
          end
        when :recent
          @studies = @studies.sort_by { |study| self.class.get_study_attribute(study, :created_at) }.reverse
        when :popular
          @studies = @studies.sort_by { |study| self.class.get_study_attribute(study, :view_count) }.reverse
        else
          # we have sort_type of :none, so order by most recent initialized studies
          # in order to sort by multiple attributes, use array notation to indicate which attribute to sort by first
          # boolean values must be converted to an integer in order for this to work
          @studies = @studies.sort_by do |study|
            [
              self.class.get_study_attribute(study, :initialized) ? 1 : 0,
              self.class.get_study_attribute(study, :created_at)
            ]
          end.reverse
        end

        # attempt to promote an exact text-string match, if possible
        if params[:terms].present?
          @studies, @match_by_data = self.class.promote_exact_match(params[:terms], @studies, @match_by_data)
        end

        # save list of study accessions for bulk_download/bulk_download_size calls, in order of results
        @matching_accessions = @studies.map { |study| self.class.get_study_attribute(study, :accession) }
        logger.info "Total matching accessions from all non-inferred searches: #{@matching_accessions}"

        # if a user ran a faceted search, attempt to infer results by converting filter display values to keywords
        # Do not run inferred search if we have a preset search with an accession list
        if @facets.any? && @accession_list.nil?
          # preserve existing search terms, if present
          facets_to_keywords = @term_list.present? ? {keywords: @term_list.dup} : {}
          facets_to_keywords.merge!(self.class.convert_filters_for_inferred_search(facets: @facets))
          # only run inferred search if we have extra keywords to run; numeric facets do not generate inferred searches
          if facets_to_keywords.any?
            @inferred_terms = facets_to_keywords.values.flatten
            logger.info "Running inferred search using #{facets_to_keywords}"
            search_match_obj = ::StudySearchService.generate_mongo_query_by_context(terms: facets_to_keywords,
                                                                                    base_studies: @viewable,
                                                                                    accessions: @matching_accessions,
                                                                                    query_context: :inferred)
            @inferred_studies = search_match_obj[:studies]
            # if gene search is being run, append new results
            if params[:genes].present? && @inferred_studies.any?
              new_genes = ::StudySearchService.find_studies_by_gene_param(params[:genes], @inferred_studies.pluck(:id))
              @gene_results[:genes_by_study].merge!(new_genes[:genes_by_study])
              @gene_results[:study_ids] += new_genes[:study_ids]
              # only show results where we found a hit in gene search
              @inferred_studies = Study.where(:id.in => new_genes[:study_ids])
            end
            @inferred_accessions = @inferred_studies.pluck(:accession)
            logger.info "Found #{@inferred_accessions.count} inferred matches: #{@inferred_accessions}"
            @matching_accessions += @inferred_accessions
            @studies += @inferred_studies.sort_by { |study| -study.search_weight(@inferred_terms)[:total] }
          end
        end

        @matching_accessions = @studies.map { |study| self.class.get_study_attribute(study, :accession) }

        logger.info "Final list of matching studies: #{@matching_accessions}"
        @results = @studies.paginate(page: params[:page], per_page: Study.per_page)
        render json: search_results_obj, status: 200
      end

      swagger_path '/search/facets' do
        operation :get do
          key :tags, [
              'Search'
          ]
          key :summary, 'Get all available facets'
          key :description, 'Returns a list of all available search facets, including filter values'
          key :operationId, 'search_facets_path'
          parameter do
            key :name, :scpbr
            key :in, :query
            key :description, 'Requested branding group (to filter facets on)'
            key :reqired, false
            key :type, :string
          end
          response 200 do
            key :description, 'Array of SearchFacets'
            schema do
              key :type, :array
              key :title, 'Array'
              items do
                key :title, 'SearchFacetConfig'
                key :'$ref', :SearchFacetConfig
              end
            end
          end
          response 406 do
            key :description, ApiBaseController.not_acceptable
          end
        end
      end

      def facets
        if @selected_branding_group.present?
          @search_facets = @selected_branding_group.facets
        else
          @search_facets = SearchFacet.visible
        end
      end

      swagger_path '/search/facet_filters' do
        operation :get do
          key :tags, [
              'Search'
          ]
          key :summary, 'Search matching filters for a facet'
          key :description, 'Returns a list of matching facet filters for a given facet'
          key :operationId, 'search_facet_filters_path'
          parameter do
            key :name, :facet
            key :in, :query
            key :description, 'Identifier of facet'
            key :required, true
            key :type, :string
          end
          parameter do
            key :name, :query
            key :in, :query
            key :description, 'User-supplied query string'
            key :required, true
            key :type, :string
          end
          response 200 do
            key :description, 'SearchFacet with matching filters'
            schema do
              key :title, 'SearchFacetQuery'
              key :'$ref', :SearchFacetQuery
            end
          end
          response 406 do
            key :description, ApiBaseController.not_acceptable
          end
          response 500 do
            key :description, 'Server error'
          end
        end
      end

      def facet_filters
        # sanitize query string for regexp matching
        @query_string = params[:query]
        query_matcher = /#{Regexp.escape(@query_string)}/i
        filter_list = @search_facet.filters_for_user(current_api_user)
        @matching_filters = filter_list.select { |filter| filter[:name] =~ query_matcher }
      end

      private

      def set_branding_group
        @selected_branding_group = BrandingGroup.find_by(name_as_id: params[:scpbr])
      end

      def set_preset_search
        @preset_search = PresetSearch.find_by(identifier: params[:preset_search])
      end

      def set_search_facet
        @search_facet = SearchFacet.find_by(identifier: params[:facet])
      end

      def set_search_facets_and_filters
        @facets = []
        if params[:facets].present?
          facet_queries = RequestUtils.split_query_param_on_delim(parameter: params[:facets], delimiter: FACET_DELIMITER)
          facet_queries.each do |query|
            facet_id, raw_filters = RequestUtils.split_query_param_on_delim(parameter: query, delimiter: ':')
            filter_values = RequestUtils.split_query_param_on_delim(parameter: raw_filters, delimiter: FILTER_DELIMITER)
            facet = SearchFacet.find_by(identifier: facet_id)
            if facet.present?
              matching_filters = self.class.find_matching_filters(facet: facet, filter_values: filter_values)
              if matching_filters.any?
                @facets << {
                    id: facet.identifier,
                    filters: matching_filters,
                    db_facet: facet # used for lookup later in :generate_bq_query_string
                }
              end
            end
          end
        end
      end

      # sanitize search values
      def sanitize_search_values(terms)
        if terms.is_a?(Array)
          sanitized = terms.map {|t| view_context.sanitize(t)}
          sanitized.join(',')
        else
          view_context.sanitize(terms)
        end
      end

      # extract study attribute (like accession) accounting for source (SCP vs. external)
      def self.get_study_attribute(search_result, attribute)
        if search_result.is_a?(Study)
          search_result.send(attribute)
        else
          search_result[attribute]
        end
      end

      # extract any "quoted phrases" from query string and tokenize terms
      def self.extract_phrases_from_search(query_string:)
        terms = []
        query_string.split('"').each do |substring|
          # when splitting on double quotes, phrases will not have any leading/trailing space
          # individual lists of terms will have one or the other, which is how we differentiate
          # stop words should be excluded from this list as they are irrelevant in a search context, but should be
          # honored in a quoted string as that is looking for an exact match
          if substring.start_with?(' ') || substring.end_with?(' ')
            terms += reject_stop_words_from_terms(substring.strip.split)
          else
            terms << substring
          end
        end
        terms.delete_if(&:blank?) # there is usually one blank entry if we had a quoted phrase, so remove it
      end

      # exclude known stop words from a list of terms to increase search result relevance
      def self.reject_stop_words_from_terms(terms)
        terms&.reject { |t| ::StudySearchService::STOP_WORDS.include? t } || []
      end

      # ascertain if there is an exact match for the entire text-based search and promote result
      # stripping non-word characters makes matching easier as it is whitespace tolerant
      def self.promote_exact_match(search_string, studies, match_data)
        safe_search_string = RequestUtils.format_text_for_match(search_string)
        reordered = studies.partition do |study|
          safe_study_name = RequestUtils.format_text_for_match(get_study_attribute(study, :name))
          safe_study_name == safe_search_string
        end.flatten
        if reordered.first != studies.first
          match_data.merge!({ 'numResults:scp:exactTitle': 1 })
        end
        [reordered, match_data]
      end

      # convert a list of facet filters into a keyword search for inferred matching
      # treats each facet separately so we can find intersection across all
      def self.convert_filters_for_inferred_search(facets:)
        terms_by_facet = {}
        facets.each do |facet|
          search_facet = facet[:db_facet]
          # only use non-numeric facets
          if search_facet.is_numeric?
            # we can't do inferred matching on numerics, and because the facets are ANDed,
            # the presence of any numeric facets disables inferred search
            return {}
          end
          terms_by_facet[search_facet.identifier] = facet[:filters].map {|filter| filter[:name]}
        end
        terms_by_facet
      end

      # build a match of studies to facets/filters used in search (for labeling studies in UI with matches)
      def self.match_studies_by_facet(query_results, search_facets)
        matches = {}
        query_results.each do |result|
          accession = result[:study_accession]
          matches[accession] ||= {facet_search_weight: 0}
          result.keys.keep_if { |key| key != :study_accession }.each do |key|
            facet_name = key.to_s.chomp('_val')
            next if facet_name.ends_with?('_label') # ignore __ontology_label queries as we'll match on the main one

            matching_filter = match_results_by_filter(search_result: result, result_key: key, facets: search_facets)
            # there may not be a matching filter if the facet was OR'ed
            if matching_filter
              matches[accession][facet_name] ||= []
              if !matches[accession][facet_name].include?(matching_filter)
                matches[accession][facet_name] << matching_filter
                matches[accession][:facet_search_weight] += 1
              end
            end
          end
        end
        matches
      end

      # find matching filters within a given facet based on query parameters
      def self.find_matching_filters(facet:, filter_values:)
        matching_filters = []
        if facet.is_numeric?
          # if we have more than two values, we likely have a unit parameter and need to convert values
          if filter_values.size > 2 && SearchFacet::TIME_UNITS.include?(filter_values.last)
            requested_unit = filter_values.slice!(-1)
          end
          min_value, max_value = filter_values.map(&:to_f)
          facet_min = facet.min.dup
          facet_max = facet.max.dup
          # if unit was sent in query, convert
          if requested_unit.present? && facet.must_convert?
            facet_min = facet.convert_time_between_units(base_value: facet_min, original_unit: facet.unit, new_unit: requested_unit)
            facet_max = facet.convert_time_between_units(base_value: facet_max, original_unit: facet.unit, new_unit: requested_unit)
          end
          if min_value >= facet_min || max_value <= facet_max
            matching_filters = {min: min_value, max: max_value, unit: requested_unit}
          end
        else
          filters_list = facet.filters_with_external.any? ? facet.filters_with_external : facet.filters
          filters_list.each do |filter|
            if filter_values.include?(filter[:id]) || filter_values.include?(filter[:name])
              matching_filters << filter
            end
          end
        end
        matching_filters
      end

      # build a map of facet filter matches to studies for computing simplistic weights for scoring
      def self.match_results_by_filter(search_result:, result_key:, facets:)
        facet_name = result_key.to_s.chomp('_val')
        matching_facet = facets.detect { |facet| facet[:id] == facet_name }
        db_facet = matching_facet[:db_facet]
        if db_facet.is_numeric?
          match = matching_facet[:filters].dup
          match.delete(:name)
          match
        else
          matching_facet[:filters].detect do |filter|
            filters = search_result[result_key].is_a?(Array) ? search_result[result_key] : [search_result[result_key]]
            filters.include?(filter[:id]) || filters.include?(filter[:name])
          end
        end
      end

      # properly escape any single quotes in a filter value (double quotes are correctly handled already)
      def self.sanitize_filter_value(filter)
        filter.gsub(/'/) { "\\'" }
      end
    end
  end
end
