# search methods specific to Human Cell Atlas Azul service
class AzulSearchService
  # map of bulk download file types to extensions (for grouping in bulk download modal)
  # tar archives are lumped in with analysis_file entries as they could be either
  FILE_EXT_BY_DOWNLOAD_TYPE = {
    'sequence_file' => %w[bam bai fastq].map { |e| [e, e + '.gz'] }.flatten,
    'analysis_file' => %w[loom csv tsv txt mtx Rdata tar h5ad pdf].map { |e| [e, e + '.gz'] }.flatten
  }.freeze

  # list of keys for an individual result entry used for matching facet filter values
  # each Azul result entry under 'hits' will have these keys, whether project- or file-based
  RESULT_FACET_FIELDS = %w[protocols samples specimens cellLines donorOrganisms organoids cellSuspensions].freeze

  def self.append_results_to_studies(existing_studies, selected_facets:, terms:, facet_map: nil, results_matched_by_data: nil)
    # set facet_map to {}, even if facet_map is explicitly passed in as nil
    facet_map ||= {}
    results_matched_by_data ||= {}
    azul_results = ::AzulSearchService.get_results(selected_facets: selected_facets, terms: terms)
    Rails.logger.info "Found #{azul_results.keys.size} results in Azul"
    azul_results.each do |accession, azul_result|
      existing_studies << azul_result
      facet_map[accession] = azul_result[:facet_matches]
    end
    results_matched_by_data['numResults:azul'] = azul_results.size
    results_matched_by_data['numResults:total'] = results_matched_by_data['numResults:scp'].to_i + azul_results.size
    { studies: existing_studies, facet_map: facet_map, results_matched_by_data: results_matched_by_data }
  end

  # execute a search against Azul API
  def self.get_results(selected_facets:, terms:)
    client = ApplicationController.hca_azul_client
    results = {}
    facet_query = client.format_query_from_facets(selected_facets) if selected_facets
    terms_to_facets = client.format_facet_query_from_keyword(terms) if terms
    term_query = client.format_query_from_facets(terms_to_facets) if terms_to_facets
    query_json = client.merge_query_objects(facet_query, term_query)
    # abort search if no facets/terms result in query to execute
    return {} if query_json.empty?

    merged_facets = merge_facet_lists(selected_facets, terms_to_facets)
    Rails.logger.info "Executing Azul project query with: #{query_json}"
    # determine if this is a normal faceted search (1 request), or term-based (split into separate requests and join)
    search_method = terms_to_facets ? :projects_by_facet : :projects
    project_results = client.send(search_method, query: query_json)
    project_results['hits'].each do |entry|
      entry_hash = entry.with_indifferent_access
      submission_date = entry_hash[:dates].first[:submissionDate]
      project_hash = entry_hash[:projects].first # there will only ever be one project here
      short_name = project_hash[:projectShortname]
      project_id = project_hash[:projectId]
      result = {
        hca_result: true,
        accession: short_name,
        name: project_hash[:projectTitle],
        description: project_hash[:projectDescription],
        hca_project_id: project_id,
        created_at: submission_date, # for sorting purposes
        view_count: 0, # for sorting purposes
        facet_matches: {},
        term_matches: [],
        term_search_weight: 0,
        file_information: [
          {
            project_id: project_id,
            file_type: 'Project Manifest',
            count: 1,
            upload_file_size: 1.megabyte, # placeholder filesize as we don't know until manifest is downloaded
            name: "#{short_name}.tsv"
          }
        ]
      }.with_indifferent_access
      # extract file summary information from result
      project_file_info = extract_file_information(entry_hash)
      result[:file_information] += project_file_info if project_file_info.any?
      # get facet matches from rest of entry
      result[:facet_matches] = get_facet_matches(entry_hash, merged_facets)
      if terms
        # only store result if we get a text match on project name/description
        match_info = get_search_term_weights(result, terms)
        if match_info[:total] > 0
          result[:term_matches] = match_info[:terms].keys
          result[:term_search_weight] = match_info[:total]
          results[short_name] = result
        end
      else
        results[short_name] = result
      end
    end
    results
  end

  # iterate through the result entries for each project to determine what facets/filters were matched
  def self.get_facet_matches(result, facets)
    results_info = {}
    facets.each do |facet|
      next if facet[:keyword_conversion]

      facet_name = facet[:id]
      RESULT_FACET_FIELDS.each do |result_field|
        azul_name = FacetNameConverter.convert_schema_column(:alexandria, :azul, facet_name)
        # gotcha where sampleDisease is called disease in Azul response objects
        azul_name = 'disease' if azul_name == 'sampleDisease'
        field_entries = result[result_field].map { |entry| entry[azul_name] }.flatten.uniq
        if facet[:filters].is_a? Hash # this is a numeric facet, and we only have one right now
          results_info[facet_name] = [facet[:filters]]
        else
          facet[:filters].each do |filter|
            match = field_entries.select { |entry| filter[:name] == entry || filter[:id] == entry }
            results_info[facet_name] ||= []
            if match.any? && !results_info[facet_name].include?(filter)
              results_info[facet_name] << filter
            end
          end
        end
      end
    end
    # compute weight based off of number of filter hits
    results_info[:facet_search_weight] = results_info.values.map(&:count).flatten.reduce(0, :+)
    results_info
  end

  # retrieve all possible facet/filter values present in Azul
  # this is done by executing an empty search and requesting only 1 project, then retrieving the
  # "termFacets" information from the response
  def self.get_all_facet_filters
    begin
      client = ApplicationController.hca_azul_client
      raw_facets = client.projects(query: {}, size: 1)['termFacets']
      mappable_facets = raw_facets.select { |facet, _| FacetNameConverter.schema_has_column?(:azul, :alexandria, facet) }
      mappable_facets.map do |facet_name, terms_hash|
        converted_name = FacetNameConverter.convert_schema_column(:azul, :alexandria, facet_name)
        all_terms = terms_hash['terms'].select { |t| t['term'].present? }
        if converted_name == 'organism_age'
          # special handling for age facet, get min/max info, but only for "years", as we normalize to that
          unit = 'year'
          unit_entries = all_terms.select { |term| term.dig('term', 'unit') == unit }
          min, max = unit_entries.map { |term| term.dig('term', 'value').to_f }.flatten.minmax
          { converted_name => { min: min, max: max, unit: 'years', is_numeric: true } }
        else
          { converted_name => { filters: all_terms.map { |t| t['term'] }, is_numeric: false } }
        end
      end.reduce({}, :merge).with_indifferent_access
    rescue RestClient::Exception => e
      Rails.logger.error "Error in retrieving facet/filter values from Azul -- #{e.class}: #{e.message}"
      ErrorTracker.report_exception(e, nil, {})
      {} # failover case to prevent NoMethodError downstream
    end
  end

  # merge together two lists of facets (from keyword- and faceted-search requests)
  # takes into account nil objects
  def self.merge_facet_lists(*facet_lists)
    all_facets = {}
    facet_lists.compact.each do |facet_list|
      # filter 'converted' facet matches so we don't show match badges in the UI
      facet_list.reject { |facet| facet[:keyword_conversion] }.each do |facet|
        facet_identifier = facet[:id]
        all_facets[facet_identifier] ||= facet
        # this is a numeric facet, and we only have one right now
        next if facet[:filters].is_a? Hash

        facet[:filters].each do |f|
          all_facets[facet_identifier][:filters] << f unless all_facets.dig(facet_identifier, :filters).include? f
        end
      end
    end
    all_facets.map { |id, facet| { id: id, filters: facet[:filters] } }
  end

  # compute a term matching weights for a result from Azul
  # this mirrors Study#search_weight
  def self.get_search_term_weights(result, terms)
    weights = {
      total: 0,
      terms: {}
    }
    terms.each do |term|
      text_blob = "#{result['name']} #{result['description']}"
      score = text_blob.scan(/#{::Regexp.escape(term)}/i).size
      if score > 0
        weights[:total] += score
        weights[:terms][term] = score
      end
    end
    weights.with_indifferent_access
  end

  # extract preliminary file information from an Azul result object
  def self.extract_file_information(result)
    project_hash = result[:projects].first # there will only ever be one project here
    short_name = project_hash[:projectShortname]
    project_id = project_hash[:projectId]
    result[:fileTypeSummaries].map do |file_summary|
      file_info = {
        source: 'hca',
        count: file_summary['count'],
        upload_file_size: file_summary['totalSize'],
        file_format: file_summary['format'],
        accession: short_name,
        project_id: project_id,
        is_intermediate: file_summary['isIntermediate']
      }
      content = file_summary['contentDescription']
      assigned_file_type = 'other'
      case content
      when /Matrix/
        assigned_file_type = is_analysis_file(file_summary) ? 'analysis_file' : 'contributed_analysis_file'
      when /Sequence/
        assigned_file_type = 'sequence_file'
      else
        # fallback to guess file_type by extension
        FILE_EXT_BY_DOWNLOAD_TYPE.each_pair do |file_type, extensions|
          if extensions.include? file_summary['format']
            if file_type == 'analysis_file' && !is_analysis_file(file_summary)
              assigned_file_type = 'contributed_analysis_file'
            else
              assigned_file_type = file_type
            end
          end
        end
      end
      file_info[:file_type] = assigned_file_type
      file_info.with_indifferent_access
    end
  end

  # see SCP-3982 for the criteria for what we want to treat as the analyis files proper
  def self.is_analysis_file(file_summary)
    file_summary['isIntermediate'] == false &&
      file_summary['fileSource'].include?('DCP/2 Analysis') &&
      file_summary['format'] == 'loom'
  end

  # query Azul with project shortnames and return summary file information
  # this method mirrors interface on BulkDownloadService#study_download_info for use in bulk download modal
  def self.get_file_summary_info(accessions)
    client = ApplicationController.hca_azul_client
    file_query = { 'project' => { 'is' => accessions } }
    results = client.projects(query: file_query)
    results['hits'].map do |entry|
      entry_hash = entry.with_indifferent_access
      project_hash = entry_hash[:projects].first # there will only ever be one project here
      accession = project_hash[:projectShortname]
      result = {
        study_source: 'HCA',
        name: project_hash[:projectTitle],
        accession:,
        description: project_hash[:projectDescription],
        studyFiles: [
          {
            project_id: project_hash[:projectId],
            file_type: 'Project Manifest',
            count: 1,
            upload_file_size: 1.megabyte, # placeholder filesize as we don't know until manifest is downloaded
            name: "#{accession}.tsv"
          }
        ]
      }.with_indifferent_access
      project_file_info = extract_file_information(entry_hash)
      result[:studyFiles] += project_file_info if project_file_info.any?
      result
    end
  end
end
