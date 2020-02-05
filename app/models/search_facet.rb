##
# SearchFacet: cached representation of convention cell metadata that has been loaded into BigQuery.  This data is
# used to render faceted search UI components faster and more easily than round-trip calls to BigQuery
#

class SearchFacet
  include Mongoid::Document
  include Mongoid::Timestamps

  extend ErrorTracker

  field :name, type: String
  field :identifier, type: String
  field :filters, type: Array, default: []
  field :is_ontology_based, type: Boolean, default: false
  field :ontology_urls, type: Array, default: []
  field :is_array_based, type: Boolean
  field :big_query_id_column, type: String
  field :big_query_name_column, type: String
  field :convention_name, type: String
  field :convention_version, type: String

  validates_presence_of :name, :identifier, :big_query_id_column, :big_query_name_column, :convention_name, :convention_version
  validates_uniqueness_of :big_query_id_column, scope: [:convention_name, :convention_version]
  validate :ensure_ontology_url_format, if: proc {|attributes| attributes[:is_ontology_based]}
  before_create :set_is_array_based_from_bq, if: proc {|attributes| attributes[:is_array_based].nil?}

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

  # return a formatted object to use to render search UI component
  def facet_config
    {
        name: self.name,
        id: self.identifier,
        links: self.ontology_urls,
        filters: self.filters
    }
  end

  # retrieve unique values from BigQuery and format an array of hashes with :name and :id values to populate :filters attribute
  def get_unique_filter_values
    Rails.logger.info "Updating filter values for SearchFacet: #{self.name} using id: #{self.big_query_id_column} and name: #{self.big_query_name_column}"
    queries = []
    if self.is_array_based
      queries << self.generate_array_query(self.big_query_id_column, 'id')
      queries << self.generate_array_query(self.big_query_name_column, 'name')
    else
      queries << self.generate_non_array_query
    end
    begin
      results = []
      queries.each do |query_string|
        Rails.logger.info "Executing query: #{query_string}"
        results << SearchFacet.big_query_dataset.query(query_string)
      end
      return assemble_filters_array(results)
    rescue => e
      Rails.logger.error "Error retrieving unique values for #{CellMetadatum::BIGQUERY_TABLE}: #{e.class.name}:#{e.message}"
      error_context = ErrorTracker.format_extra_context({queries: queries})
      ErrorTracker.report_exception(e, nil, error_context)
      []
    end
  end

  # update cached filters in place with new values
  def update_filter_values!
    values = self.get_unique_filter_values.to_a
    unless values.empty?
      self.update(filters: values)
    else
      false # did not get any results back, meaning :retrieve_unique_filter_values encountered an error
    end
  end

  # generate a single query to get DISTINCT values from an array-based column, preserving order
  # this way we can do two queries, and stitch them together in a hash as the order will be the same
  # e.g. IDs will line up with NAMEs
  def generate_array_query(column_name, identifier)
    "SELECT DISTINCT #{identifier} FROM(SELECT array_col AS #{identifier}, " + \
    "FROM #{CellMetadatum::BIGQUERY_TABLE}, UNNEST(#{column_name}) AS array_col " + \
    "WITH OFFSET AS offset ORDER BY offset)"
  end

  # generate query string to retrieve distinct values for non-array based facets
  def generate_non_array_query
    "SELECT DISTINCT #{self.big_query_id_column} AS id, #{self.big_query_name_column} AS name FROM #{CellMetadatum::BIGQUERY_TABLE}"
  end

  # stitch together results into the formatted filters array based on whether or not we ran one or two queries
  def assemble_filters_array(results_array)
    if results_array.size == 1
      results_array.first # already in the correct form, so just return
    else
      # we have two hashes we need to merge together
      filters_array = []
      id_array = results_array.first
      name_array = results_array.last
      id_array.each_with_index do |filter_hash, index|
        filters_array << filter_hash.merge(name_array[index])
      end
      filters_array
    end
  end

  private

  # determine if this facet references array-based data in BQ as data_type will look like "ARRAY<STRING>"
  def set_is_array_based_from_bq
    column_schema = SearchFacet.get_table_schema(column_name: self.big_query_id_column)
    self.is_array_based = column_schema[:data_type].include?('ARRAY')
  end

  # custom validator for checking ontology_urls array
  def ensure_ontology_url_format
    if self.ontology_urls.blank?
      errors.add(:ontology_urls, "cannot be empty if SearchFacet is ontology-based")
    else
      self.ontology_urls.each do |ontology_url|
        # check that entry is a Hash with :name and :url field
        unless ontology_url.is_a?(Hash) && ontology_url.with_indifferent_access.keys.sort == %w(name url)
          errors.add(:ontology_urls, "contains a misformed entry: #{ontology_url}. Must be a Hash with a :name and :url field")
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
