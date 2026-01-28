# collection of methods for searching studies
class StudySearchService

  MAX_GENE_SEARCH = 50
  MAX_GENE_SEARCH_MSG = "For performance reasons, gene search is limited to #{MAX_GENE_SEARCH} genes, except for  " \
                        'pre-processed dot plots (where available). ' \
                        'Please use multiple searches to view more genes.'.freeze

  # list of common 'stop words' to scrub from term-based search requests
  # these are unhelpful in search contexts as they artificially inflate irrelevant results
  # from https://gist.github.com/sebleier/554280
  STOP_WORDS = %w[i me my myself we our ours ourselves you your yours yourself yourselves he him his himself she
                  her hers herself it its itself they them their theirs themselves what which who whom this that
                  these those am is are was were be been being have has had having do does did doing a an the and
                  but if or because as until while of at by for with about against between into through during
                  before after above below to from up down in out on off over under again further then once here
                  there when where why how all any both each few more most other some such no nor not only own same
                  so than too very s t can will just don should now].freeze

  def self.find_studies_by_gene_param(gene_param, study_ids)
    genes = sanitize_gene_params(gene_param)
    find_studies_by_genes(genes, study_ids)
  end

  # genes is an array of gene ids/names
  # study_ids is a list of study ids to limit the search to.
  # returns a hash of unique study ids, and also a hash of gene ids by study id
  def self.find_studies_by_genes(genes, study_ids)

    # limit gene search for performance reasons
    gene_matches = []

    gene_matches = Gene.where(:study_id.in => study_ids)
                       .any_of({:name.in => genes},
                               {:searchable_name.in => genes.map(&:downcase)},
                               {:gene_id.in => genes})
    gene_match_list = gene_matches.pluck(:id, :searchable_name, :study_id)
    genes_by_study = {}
    study_ids = []
    gene_match_list.map do |match|
      genes_by_study[match[2]] ||= []
      genes_by_study[match[2]].push(match[1])
      study_ids = study_ids.push(match[2])
    end
    { genes_by_study: genes_by_study, study_ids: study_ids.uniq }
  end

  # takes a gene param string and returns a sanitized, leading/trailing space-stripped array of terms
  def self.sanitize_gene_params(genes)
    delimiter = genes.include?(',') ? ',' : ' '
    raw_genes = genes.split(delimiter)
    gene_array = RequestUtils.sanitize_search_terms(raw_genes).split(',').map(&:strip)
    # limit gene search for performance reasons
    if gene_array.size > MAX_GENE_SEARCH
      gene_array = gene_array.take(MAX_GENE_SEARCH)
    end
    gene_array.map(&:strip)
  end

  # generate a Mongoid::Criteria object to perform a keyword/exact phrase search based on contextual use case
  # supports the following query_contexts: :keyword (individual terms), :phrase (quoted phrases & keywords)
  # and :inferred (converting a facet-based query to keywords)
  # will scope the query based off of :base_studies, and include/exclude studies matching
  # :accessions based on the :query_context (included by default, but excluded in :inferred to avoid duplicates)
  def self.generate_mongo_query_by_context(terms:, base_studies:, accessions:, query_context:)
    case query_context
    when :keyword
      author_match_study_ids = Author.where(:$text => { :$search => terms }).pluck(:study_id)

      matches_by_text = base_studies.where({ :$text => { :$search => terms } })
      metadata_matches = get_studies_from_term_conversion(terms.split)
      matches_by_metadata = base_studies.where({ :accession.in => metadata_matches.keys })
      matches_by_accession = base_studies.where({ :accession.in => accessions })
      matches_by_author = base_studies.where({ :id.in => author_match_study_ids })

      results_matched_by_data = {
        'numResults:scp:accession': matches_by_accession.length,
        'numResults:scp:text': matches_by_text.length,
        'numResults:scp:author': matches_by_author.length,
        'numResults:scp:metadata': metadata_matches.keys.length
      }

      studies = base_studies.any_of(matches_by_text, matches_by_accession, matches_by_author, matches_by_metadata)
      results_matched_by_data['numResults:scp'] = studies.length
      results_matched_by_data['numResults:total'] = studies.length

      { studies: studies, results_matched_by_data: results_matched_by_data, metadata_matches: metadata_matches }
    when :phrase
      study_regex = escape_terms_for_regex(term_list: terms)
      author_match_study_ids = Author.any_of({ first_name: study_regex },
                                             { last_name: study_regex },
                                             { institution: study_regex }).pluck(:study_id)

      matches_by_name = base_studies.any_of({ name: study_regex })
      matches_by_description = base_studies.any_of({ description: study_regex })
      metadata_matches = get_studies_from_term_conversion(terms)
      matches_by_metadata = base_studies.where({ :accession.in => metadata_matches.keys })
      matches_by_accession = base_studies.where({ :accession.in => accessions })
      matches_by_author = base_studies.any_of({ :id.in => author_match_study_ids })

      # see above for notes on counts
      results_matched_by_data = {
        'numResults:scp:accession': matches_by_accession.length,
        'numResults:scp:name': matches_by_name.length,
        'numResults:scp:description': matches_by_description.length,
        'numResults:scp:author': matches_by_author.length,
        'numResults:scp:metadata': metadata_matches.keys.length
      }

      studies = base_studies.any_of(matches_by_name, matches_by_description, matches_by_accession,
                                    matches_by_author, matches_by_metadata)
      results_matched_by_data['numResults:scp'] = studies.length
      results_matched_by_data['numResults:total'] = studies.length

      { studies: studies, results_matched_by_data: results_matched_by_data, metadata_matches: metadata_matches }

    when :inferred
      # in order to maintain the same behavior as normal facets, we run each facet separately and get matching accessions
      # this gives us an array of arrays of matching accessions; now find the intersection (:&)
      filters = terms.values.map { |keywords| escape_terms_for_regex(term_list: keywords) }
      accessions_by_filter = filters.map do |filter|
        base_studies.any_of({ name: filter }, { description: filter })
                    .where(:accession.nin => accessions).pluck(:accession)
      end
      studies = base_studies.where(:accession.in => accessions_by_filter.inject(:&))
      { studies: studies, results_matched_by_data: {} }
    else
      # no matching query case, so perform normal text-index search
      studies = base_studies.any_of({ :$text => { :$search => terms } }, { :accession.in => accessions })
      { studies: studies, results_matched_by_data: {}, metadata_matches: {} }
    end
  end

  # take the output from :match_facet_filters_from_keywords and match to any possible CellMetadatum in the database
  # will return a hash of accessions to matched metadata entries
  def self.get_studies_from_term_conversion(terms)
    accessions_to_filters = {}
    filter_data = match_facet_filters_from_terms(terms)
    filter_data.each do |identifier, values|
      # we need to look in '__ontology_label' entries as well as these will include plain text entries
      metadata_names = [identifier, "#{identifier}__ontology_label"]
      matches = CellMetadatum.where(:name.in => metadata_names, :values.in => values)
      matches.each do |metadata|
        next if metadata.study.queued_for_deletion

        accession = metadata.study.accession
        accessions_to_filters[accession] ||= {}
        matched_values = values & metadata.values
        matched_filters = matched_values.map { |val| { id: val, name: val } } # mimic facet filter matches for UI
        metadata_name = metadata.name.chomp('__ontology_label') # for better labels in UI
        accessions_to_filters[accession][metadata_name] = matched_filters
      end
    end
    # compute weights for sorting, which is equivalent to the total number of filter matches
    accessions_to_filters.each do |accession, results|
      accessions_to_filters[accession][:facet_search_weight] = results.values.flatten.size
    end
    accessions_to_filters.with_indifferent_access
  end

  # search Mongo for facets that don't use BigQuery to source data
  # also accounts for presence-based facets like has_morphology
  def self.perform_mongo_facet_search(facets)
    all_facets = facets.map { |f| f[:db_facet].identifier }
    studies_to_facets = {}
    facets.each do |facet|
      db_facet = facet[:db_facet]
      filter_values = facet[:filters]
      if db_facet.is_numeric?
        values = filter_values
      else
        values = filter_values.map { |entry| [convert_id_format(entry[:id]), entry[:name]] }.flatten
      end
      matches = db_facet.associated_metadata(values:)
      matches.each do |metadata|
        next if metadata.study.queued_for_deletion

        accession = metadata.study.accession
        facet_id = db_facet.identifier
        if db_facet.is_presence_facet
          matched_values = [facet_id]
        elsif db_facet.is_numeric?
          matched_values = ["#{filter_values[:min]}-#{filter_values[:max]} #{filter_values[:unit]}"]
        else
          matched_values = values & metadata.values
        end
        matched_values.map do |val|
          studies_to_facets[accession] ||= {}
          studies_to_facets[accession][facet_id.to_sym] ||= []
          studies_to_facets[accession][facet_id.to_sym] << val
        end
      end
    end
    # filter out studies that don't match all facets
    union = studies_to_facets.select do |_, matched_facets|
      matched_facets.keys.map(&:to_s).sort == all_facets.sort
    end
    union.map do |accession, matches|
      { study_accession: accession }.merge(matches)
    end
  end

  def self.filter_results_by_data_type(studies, data_types)
    return studies if data_types.empty?

    matches = data_types.index_with { [] }
    # note: this has to be updated if a new data_type is added
    matchers = {
      raw_counts: :has_raw_counts_matrices?,
      diff_exp: :has_differential_expression_results?,
      spatial: :has_spatial_clustering?
    }

    # run matching in parallel to reduce UI blocking
    Parallel.map(studies, in_threads: 10) do |study|
      data_types.each do |data_type|
        matches[data_type] << study.accession if study.send(matchers[data_type])
      end
    end

    # find the intersection of all matches by data types
    study_matches = matches.values
    accessions = study_matches[0].intersection(*study_matches[1..])
    studies.where(:accession.in => accessions)
  end

  # deal with ontology id formatting inconsistencies
  def self.convert_id_format(id)
    parts = id.split(/[_:]/)
    [parts.join('_'), parts.join(':')]
  end

  # take a term and match to a possible search facet/filter
  # will return a single hash with keys as facet names, and values as an array of filter matches
  def self.match_facet_filters_from_terms(term_list)
    terms = term_list || []
    filters_by_facet = {}
    terms.each do |term|
      facets = SearchFacet.find_facets_from_term(term)
      next if facets.empty?

      facets.each do |facet|
        filter_list = facet.filters_with_external.any? ? :filters_with_external : :filters
        matches = facet.find_filter_word_matches(term, filter_list: filter_list)
        next if matches.empty?

        filters_by_facet[facet.identifier] ||= []
        filters_by_facet[facet.identifier] += matches
      end
    end
    filters_by_facet.with_indifferent_access
  end

  # escape regular expression control characters from list of search terms and format for search
  def self.escape_terms_for_regex(term_list:)
    escaped_terms = term_list.map {|term| Regexp.quote term}
    /(#{escaped_terms.join('|')})/i
  end
end
