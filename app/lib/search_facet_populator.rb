# Methods for populating SearchFacets, based on manual config or schema files

class SearchFacetPopulator

  EXCLUDED_BQ_COLUMNS = %w(CellID donor_id biosample_id)
  INCLUDED_OPTIONAL_COLUMNS = %w(cell_type organ_region)
  # loads the alexandria convention schema and populates search facets from it
  def self.populate_from_schema
    schema_object = alexandria_convention_config
    required_fields = schema_object['required']

    (required_fields + INCLUDED_OPTIONAL_COLUMNS).each do |field_identifier|
      if !EXCLUDED_BQ_COLUMNS.include?(field_identifier) && !field_identifier.include?('__ontology_label')
        populate_facet(field_identifier, schema_object)
      end
    end
  end

  # creates/updates a facet from a name, and returns the new SearchFacet.
  # To manually populate a new Alexandria convention facet from the rails console, run e.g.
  # SearchFacetPopulator.populate_facet('vaccination__route')
  def self.populate_facet(facet_identifier, schema_object=nil)
    if schema_object.nil?
      # default to alexandria convention
      schema_object = fetch_json_from_url(alexandria_convention_config[:url])
    end
    field_def = schema_object['properties'][facet_identifier]
    if !field_def
      throw "Unrecognized field name '#{facet_identifier}' -- could not find definition in schema"
    end
    is_ontology_based = field_def['ontology'].present?
    ontology_label_field_name = facet_identifier + '__ontology_label'

    updated_facet = SearchFacet.find_or_initialize_by(identifier: facet_identifier)
    updated_facet.name = facet_identifier.gsub(/_/, ' ')
    updated_facet.data_type = field_def['type'] == 'array' ? field_def['items']['type'] : field_def['type']
    updated_facet.is_ontology_based = is_ontology_based
    updated_facet.is_array_based = 'array'.casecmp(field_def['type']) == 0
    updated_facet.big_query_id_column = facet_identifier
    updated_facet.big_query_name_column = is_ontology_based ? ontology_label_field_name : facet_identifier
    updated_facet.convention_name = schema_object['title']
    updated_facet.convention_version = schema_object['$id'].match('alexandria_convention/(.*)/json')[1]

    if is_ontology_based
      updated_facet.ontology_urls = []
      urls = field_def['ontology'].split(',')
      browser_urls = []
      # ontology_browser_urls are stored in different places in the schema for array properties
      if field_def['ontology_browser_url']
        browser_urls = field_def['ontology_browser_url'].split(',')
      elsif field_def['items']['ontology_browser_url']
        browser_urls = field_def['items']['ontology_browser_url'].split(',')
      end
      # for each url/browser_url combo, fetch the title and add it to the facet ontology_urls array
      # use of .zip means browser_url will be nil if not provided in the schema
      urls.zip(browser_urls).each do |url, browser_url|
        ontology = fetch_json_from_url(url)
        # check if response has expected keys; if not, default to URL for name value
        ontology_name = ontology.dig('config', 'title') ? ontology['config']['title'] : url
        ontology_obj = {name: ontology_name, url: url, browser_url: browser_url}
        updated_facet.ontology_urls.push(ontology_obj)
      end
    end
    updated_facet.save!
    updated_facet
  end

  def self.alexandria_convention_config
    convention_file_location = Rails.root.join('lib', 'assets', 'metadata_schemas', 'alexandria_convention', 'alexandria_convention_schema.json')
    JSON.parse(File.read(convention_file_location))
  end

  # generic fetch of JSON from remote URL, for parsing convention schema or EBI OLS ontology entries
  def self.fetch_json_from_url(url)
    begin
      response = RestClient.get url
      JSON.parse(response.body)
    rescue RestClient::Exception => e
      Rails.logger.error "Unable to fetch JSON from #{url}: #{e.class.name}: #{e.message}"
    rescue JSON::ParserError => e
      Rails.logger.error "Unable to parse response from #{url}: #{e.class.name}: #{e.message}"
    end
  end
end
