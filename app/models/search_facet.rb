##
# SearchFacet: cached representation of convention cell metadata that has been loaded into BigQuery.  This data is
# used to render faceted search UI components faster and more easily than round-trip calls to BigQuery
#

class SearchFacet
  include Mongoid::Document
  include Mongoid::Timestamps
  include Swagger::Blocks

  extend ErrorTracker

  field :name, type: String
  field :identifier, type: String
  field :filters, type: Array, default: []
  field :is_ontology_based, type: Boolean, default: false
  field :ontology_urls, type: Array, default: []
  field :data_type, type: String
  field :is_array_based, type: Boolean
  field :big_query_id_column, type: String
  field :big_query_name_column, type: String
  field :big_query_conversion_column, type: String # for converting numeric columns with units, like organism_age
  field :convention_name, type: String
  field :convention_version, type: String
  field :unit, type: String # unit represented by values in number-based facets
  field :min, type: Float # minimum allowed value for number-based facets
  field :max, type: Float # maximum allowed value for number-based facets
  field :visible, type: Boolean, default: true # default visibility (false will not show in UI but can be queried via API)

  DATA_TYPES = %w(string number boolean)
  BQ_DATA_TYPES = %w(STRING FLOAT64 BOOL)
  BQ_TO_FACET_TYPES = Hash[BQ_DATA_TYPES.zip(DATA_TYPES)]

  # Time multipliers, from https://github.com/broadinstitute/scp-ingest-pipeline/blob/master/ingest/validation/validate_metadata.py#L785
  TIME_MULTIPLIERS = {
      years: 31557600, # (day * 365.25 to fuzzy-account for leap-years)
      months: 2626560, #(day * 30.4 to fuzzy-account for different months)
      weeks: 604800,
      days: 86400,
      hours: 3600
  }.with_indifferent_access.freeze
  TIME_UNITS = TIME_MULTIPLIERS.keys.freeze

  validates_presence_of :name, :identifier, :data_type, :big_query_id_column, :big_query_name_column, :convention_name, :convention_version
  validates_uniqueness_of :big_query_id_column, scope: [:convention_name, :convention_version]
  validate :ensure_ontology_url_format, if: proc {|attributes| attributes[:is_ontology_based]}
  before_validation :set_data_type_and_array, on: :create,
                    if: proc {|attr| (![true, false].include?(attr[:is_array_based]) || attr[:data_type].blank?) && attr[:big_query_id_column].present?}
  after_create :update_filter_values!

  swagger_schema :SearchFacet do
    key :required, [:name, :identifier, :data_type, :big_query_id_column, :big_query_name_column, :convention_name, :convention_version]
    key :name, 'SearchFacet'
    property :name do
      key :type, :string
      key :description, 'Name/category of facet'
    end
    property :identifier do
      key :type, :string
      key :description, 'ID of facet from convention JSON'
    end
    property :data_type do
      key :type, :string
      key :description, 'Data type of column entries'
      key :enum, DATA_TYPES
    end
    property :filters do
      key :type, :array
      key :description, 'Array of filter values for facet'
      items type: :object do
        key :title, 'FacetFilter'
        key :required, [:name, :id]
        property :name do
          key :type, :string
          key :description, 'Display name of filter'
        end
        property :id do
          key :type, :string
          key :description, 'ID value of filter (if different)'
        end
      end
    end
    property :is_ontology_based do
      key :type, :boolean
      key :description, 'Filter values based on ontological data'
    end
    property :ontology_urls do
      key :type, :array
      key :description, 'Array of external links to ontologies (if ontology-based)'
      items type: :object do
        key :title, 'OntologyUrl'
        key :required, [:name, :url]
        property :name do
          key :type, :string
          key :description, 'Display name of ontology'
        end
        property :url do
          key :type, :string
          key :description, 'External link to ontology'
        end
      end
    end
    property :is_array_based do
      key :type, :boolean
      key :description, 'Filter values sourced from array-based BigQuery column'
    end
    property :big_query_id_column do
      key :type, :string
      key :description, 'Column in BigQuery to source ID values from'
    end
    property :big_query_name_column do
      key :type, :string
      key :description, 'Column in BigQuery to source name values from'
    end
    property :big_query_conversion_column do
      key :type, :string
      key :description, 'Column in BigQuery to run numeric conversions against (if needed)'
    end
    property :convention_name do
      key :type, :string
      key :description, 'Name of metadata convention facet is sourced from'
    end
    property :convention_version do
      key :type, :string
      key :description, 'Version of metadata convention facet is sourced from'
    end
    property :unit do
      key :type, :string
      key :description, 'Unit for numeric facets'
      key :enum, TIME_UNITS
    end
    property :min do
      key :type, :float
      key :description, 'Minimum value for numeric facets'
    end
    property :max do
      key :type, :float
      key :description, 'Maximum value for numeric facets'
    end
  end

  swagger_schema :SearchFacetConfig do
    key :name, 'SearchFacetConfig'
    key :required, [:name, :id, :links, :filters]
    property :name do
      key :type, :string
      key :description, 'Name/category of search facet'
    end
    property :id do
      key :type, :string
      key :description, 'ID of facet from convention JSON'
    end
    property :type do
      key :type, :string
      key :description, 'Data type of column entries'
      key :enum, DATA_TYPES
    end
    property :items do
      key :title, 'ArrayItems'
      key :type, :object
      key :description, 'Individual item properties (if array based)'
      property :type do
        key :type, :string
        key :description, 'Data type of individual array items'
      end
    end
    property :filters do
      key :type, :array
      key :description, 'Array of filter values for facet'
      items type: :object do
        key :title, 'FacetFilter'
        key :required, [:name, :id]
        property :name do
          key :type, :string
          key :description, 'Display name of filter'
        end
        property :id do
          key :type, :string
          key :description, 'ID value of filter (if different)'
        end
      end
    end
    property :links do
      key :type, :array
      key :description, 'Array of external links to ontologies (if ontology-based)'
      items type: :object do
        key :title, 'OntologyUrl'
        key :required, [:name, :url]
        property :name do
          key :type, :string
          key :description, 'Display name of ontology'
        end
        property :url do
          key :type, :string
          key :description, 'External link to ontology'
        end
      end
    end
    property :unit do
      key :type, :string
      key :description, 'Unit represented by numeric values'
    end
    property :min do
      key :type, :float
      key :description, 'Minumum allowed value for numeric columns'
    end
    property :max do
      key :type, :float
      key :description, 'Maximum allowed value for numeric columns'
    end
  end

  swagger_schema :SearchFacetQuery do
    key :name, 'SearchFacetQuery'
    key :required, [:facet, :query, :filters]
    property :name do
      key :type, :string
      key :description, 'ID of facet from convention JSON'
    end
    property :type do
      key :type, :string
      key :description, 'Data type of column entries'
      key :enum, DATA_TYPES
    end
    property :query do
      key :type, :string
      key :description, 'User-supplied query string'
    end
    property :filters do
      key :type, :array
      key :description, 'Array of matching filter values for facet from query'
      items type: :object do
        key :title, 'FacetFilter'
        key :required, [:name, :id]
        property :name do
          key :type, :string
          key :description, 'Display name of filter'
        end
        property :id do
          key :type, :string
          key :description, 'ID value of filter (if different)'
        end
      end
    end
  end

  def self.big_query_dataset
    ApplicationController.big_query_client.dataset(CellMetadatum::BIGQUERY_DATASET)
  end

  # retrieve table schema definition
  def self.get_table_schema(table_name: CellMetadatum::BIGQUERY_TABLE, column_name: nil)
    begin
      query_string = "SELECT column_name, data_type, is_nullable FROM INFORMATION_SCHEMA.COLUMNS WHERE table_name='#{table_name}'"
      schema = self.big_query_dataset.query(query_string)
      if column_name.present?
        schema.detect {|column| column[:column_name] == column_name}
      else
        schema
      end
    rescue => e
      Rails.logger.error "Error retrieving table schema for #{CellMetadatum::BIGQUERY_TABLE}: #{e.class.name}:#{e.message}"
      error_context = ErrorTracker.format_extra_context({query_string: query_string})
      ErrorTracker.report_exception(e, nil, error_context)
      []
    end
  end

  # update all search facet filters after BQ update
  def self.update_all_facet_filters
    self.all.each do |facet|
      Rails.logger.info "Updating #{facet.name} filter values"
      updated = facet.update_filter_values!
      if updated
        Rails.logger.info "Update to #{facet.name} complete!"
      else
        Rails.logger.error "Update to #{facet.name} failed"
      end
    end
  end

  # return all "visible" facets
  def self.visible
    self.where(visible: true)
  end

  # helper to know if column is numeric
  def is_numeric?
    self.data_type == 'number'
  end

  # for now, assume it's time if it's numeric and has a known time unit
  def is_time_unit?
    self.is_numeric? && TIME_UNITS.include?(self.unit)
  end

  # know if a facet needs unit conversion
  def must_convert?
    self.big_query_conversion_column.present? && self.unit != 'seconds'
  end

  # convert a numeric time-based value into seconds, defaulting to declared unit type
  def calculate_time_in_seconds(base_value:, unit_label: self.unit)
    multiplier = TIME_MULTIPLIERS[unit_label]
    # cast as float to allow passing in strings from search requests as values
    base_value.to_f * multiplier
  end

  # convert a time-based value from one unit to another
  def convert_time_between_units(base_value:, original_unit:, new_unit:)
    if original_unit == new_unit
      base_value
    else
      # first convert to seconds
      value_in_seconds = self.calculate_time_in_seconds(base_value: base_value, unit_label: original_unit)
      # now divide by multiplier to get value in new unit
      denominator = TIME_MULTIPLIERS[new_unit]
      value_in_seconds.to_f / denominator
    end
  end

  # retrieve unique values from BigQuery and format an array of hashes with :name and :id values to populate :filters attribute
  def get_unique_filter_values
    Rails.logger.info "Updating filter values for SearchFacet: #{self.name} using id: #{self.big_query_id_column} and name: #{self.big_query_name_column}"
    query_string = self.generate_bq_query_string
    begin
      Rails.logger.info "Executing query: #{query_string}"
      results = SearchFacet.big_query_dataset.query(query_string)
      self.is_numeric? ? results.first : results
    rescue => e
      Rails.logger.error "Error retrieving unique values for #{CellMetadatum::BIGQUERY_TABLE}: #{e.class.name}:#{e.message}"
      error_context = ErrorTracker.format_extra_context({query_string: query_string})
      ErrorTracker.report_exception(e, nil, error_context)
      []
    end
  end

  # update cached filters in place with new values
  def update_filter_values!
    values = self.get_unique_filter_values
    unless values.empty?
      if self.is_numeric?
        self.update(min: values[:MIN], max: values[:MAX])
      else
        self.update(filters: values.to_a)
      end
    else
      false # did not get any results back, meaning :retrieve_unique_filter_values encountered an error
    end
  end

  # return the correct query string for updating filter values from BQ based on facet type
  def generate_bq_query_string
    if self.is_array_based
      self.generate_array_query
    elsif self.is_numeric?
      self.generate_minmax_query
    else
      self.generate_non_array_query
    end
  end

  # generate a single query to get DISTINCT values from an array-based column, preserving order
  def generate_array_query
    "SELECT DISTINCT id, name FROM(SELECT id_col AS id, name_col as name " + \
    "FROM #{CellMetadatum::BIGQUERY_TABLE}, UNNEST(#{self.big_query_id_column}) AS id_col WITH OFFSET id_pos, " + \
    "UNNEST(#{self.big_query_name_column}) as name_col WITH OFFSET name_pos WHERE id_pos = name_pos) WHERE id IS NOT NULL " + \
    "ORDER BY LOWER(name)"
  end

  # generate query string to retrieve distinct values for non-array based facets
  def generate_non_array_query
    "SELECT DISTINCT #{self.big_query_id_column} AS id, #{self.big_query_name_column} AS name FROM #{CellMetadatum::BIGQUERY_TABLE} " + \
    "WHERE #{self.big_query_id_column} IS NOT NULL ORDER BY LOWER(#{self.big_query_name_column})"
  end

  # generate a minmax query string to set bounds for numeric facets
  def generate_minmax_query
    "SELECT MIN(#{self.big_query_id_column}) AS MIN, MAX(#{self.big_query_id_column}) AS MAX FROM #{CellMetadatum::BIGQUERY_TABLE}"
  end

  private

  # determine if this facet references array-based data in BQ as data_type will look like "ARRAY<STRING>"
  def set_data_type_and_array
    column_schema = SearchFacet.get_table_schema(column_name: self.big_query_id_column)
    detected_type = column_schema[:data_type]
    self.is_array_based = detected_type.include?('ARRAY')
    item_type = BQ_DATA_TYPES.detect {|d| detected_type.match(d).present?}
    self.data_type = BQ_TO_FACET_TYPES[item_type]
  end

  # custom validator for checking ontology_urls array
  def ensure_ontology_url_format
    if self.ontology_urls.blank?
      errors.add(:ontology_urls, "cannot be empty if SearchFacet is ontology-based")
    else
      self.ontology_urls.each do |ontology_url|
        # check that entry is a Hash with :name and :url field
        unless ontology_url.is_a?(Hash) && ontology_url.with_indifferent_access.keys.sort == %w(browser_url name url)
          errors.add(:ontology_urls, "contains a misformed entry: #{ontology_url}. Must be a Hash with a :name, :url, and :browser_url field")
        end
        santized_url = ontology_url.with_indifferent_access
        unless url_valid?(santized_url[:url])
          errors.add(:ontology_urls, "contains an invalid URL: #{santized_url[:url]}")
        end
      end
    end
  end

  # a URL may be technically well-formed but may
  # not actually be valid, so this checks for both.
  def url_valid?(url)
    url = URI.parse(url) rescue false
    url.kind_of?(URI::HTTP) || url.kind_of?(URI::HTTPS)
  end
end
