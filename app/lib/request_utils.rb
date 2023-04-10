# RequestUtils: helper class for dealing with request parameters, sanitizing input, and setting
# cache paths on visualization requests
class RequestUtils
  # list of parameters to reject from :get_cache_key as they will be represented by request.path
  # format is always :json and therefore unnecessary
  # reviewerSession should be ignored as it is not a valid visualization parameter
  CACHE_PATH_EXCLUDE_LIST = %w[controller action format study_id reviewerSession].freeze

  # character regex to convert into underscores (_) for cache path setting
  PATH_REGEX = %r{(\/|%2C|%2F|%20|\?|&|=|\.|,|\s)}.freeze

  # load same sanitizer as ActionView for stripping html/js from inputs
  # using FullSanitizer as it is the most strict
  SANITIZER ||= Rails::Html::FullSanitizer.new

  ##
  # Cache path methods
  ##

  # get a unique cache path for an individual request
  # will result in paths with fixed lengths, such as
  # _single_cell_api_v1_clusters_SCP1234_f6c41dbf8f1760d7dc1b36a3db7c05ec56049a0bdc54644639005c0e41bd7490
  def self.get_cache_path(request_path, url_params)
    # transform / into _ to avoid encoding as %2f
    sanitized_path = sanitize_value_for_cache(request_path)
    digest_key = construct_params_digest(url_params)
    [sanitized_path, digest_key].join('_')
  end

  # create a unique hex digest for a hash of request parameters
  # parameters are sorted to ensure idempotency of resulting digest, which is critical for cache management
  # this prevents long parameter lists from being split in the middle due to maximum filename length limits
  # and resulting in invalid % encoding issue when trying to clear selected cache entries
  def self.construct_params_digest(params)
    sorted_params = params.reject { |name, value| CACHE_PATH_EXCLUDE_LIST.include?(name) || value.empty? }
                          .sort_by { |key, _| key }.flatten
    return '' if sorted_params.empty? # gotcha to prevent converting empty string into hexdigest

    Digest::SHA256.hexdigest sorted_params.join
  end

  ##
  # Sanitizer methods
  ##

  # remove url-encoded characters from request paths & parameter values
  # extra gsub at the end will catch any mangled encodings and trim them
  def self.sanitize_value_for_cache(value)
    value.gsub(PATH_REGEX, '_').gsub(/(%|\/)/, '')
  end

  # sanitizes a page param into an integer.  Will default to 1 if the value
  # is nil or otherwise can't be read
  def self.sanitize_page_param(page_param)
    page_num = 1
    parsed_num = page_param.to_i
    if (parsed_num > 0)
      page_num = parsed_num
    end
    page_num
  end

  # safely determine min/max bounds of an array, accounting for NaN value
  def self.get_minmax(values_array)
    begin
      values_array.minmax
    rescue TypeError, ArgumentError
      values_array.dup.reject! {|value| value.nil? || value.nan? }.minmax
    end
  end

  # safely strip unsafe characters and encode search parameters for query/rendering
  # strips out unsafe characters that break rendering notices/modals
  def self.sanitize_search_terms(terms)
    inputs = terms.is_a?(Array) ? terms.join(',') : terms.to_s
    SANITIZER.sanitize(inputs).encode(Encoding.find('ASCII-8BIT'), invalid: :replace, undef: :replace)
  end

  # convert a string into a format for matching
  # will strip non-word characters and extraneous whitespace and downcase to make matching easier
  def self.format_text_for_match(text)
    text.split.map { |term| term.downcase.gsub(/\W/, '') }.reject(&:blank?).join(' ')
  end

  # takes a comma-delimited string of ids (e.g. StudyFile ids) and returns an array of ids
  # raises Argument error if any of the strings are not valid ids
  def self.validate_id_list(id_list_string)
    ids = id_list_string.split(',').map(&:strip)
    ids.each {|id| validate_mongo_id(id) }
    ids
  end

  # confirms the passed-in string is a valid mongo id (24-char hex)
  # raises Argument error if not a valid id
  # returns the string for convenience in chaining
  def self.validate_mongo_id(id_string)
    begin
      BSON::ObjectId.from_string(id_string)
    rescue
      raise ArgumentError, 'IDs must be valid MongoDB ObjectId values'
    end
    id_string
  end

  # return the hostname (and port, if present) for this instance
  # e.g. "localhost", "localhost:3000", "singlecell.broadinstitute.org"
  def self.get_hostname
    url_opts = ApplicationController.default_url_options
    url_opts[:port].present? ? "#{url_opts[:host]}:#{url_opts[:port]}" : url_opts[:host]
  end

  # helper method for getting the base url with protocol, hostname, and port
  # e.g. "https://localhost"
  def self.get_base_url
    "#{ApplicationController.default_url_options[:protocol]}://#{self.get_hostname}"
  end

  # extracts an array of genes from a comma-delimited string list of gene names
  def self.get_genes_from_param(study, gene_param)
    terms = RequestUtils.sanitize_search_terms(gene_param).split(',')
    matrix_ids = study.expression_matrix_files.map(&:id)
    genes = []
    terms.each do |term|
      matches = study.genes.by_name_or_id(term, matrix_ids)
      unless matches.empty?
        genes << matches
      end
    end
    genes
  end

  # generic split function, handles type checking
  def self.split_query_param_on_delim(parameter:, delimiter: ',')
    parameter.is_a?(Array) ? parameter : parameter.to_s.split(delimiter).map(&:strip)
  end

  # returns nil if no header present, throws ArgumentError if unparseable/invalid
  # otherwise returns a hash of first_byte, last_byte, total_size
  def self.parse_content_range_header(headers)
    content_range = headers['Content-Range']
    if content_range.present?
      is_chunked = true
      range_match = content_range.match(/bytes\ (\d*)-(\d*)\/(\d*)$/)
      if range_match.nil?
        raise ArgumentError, 'Could not parse Content-Range header'
      end
      first_byte, last_byte, total_size = range_match[1..3].map{ |num| num.to_i }
      if first_byte >= last_byte || last_byte > total_size
        raise ArgumentError, 'Invalid Content-Range header range'
      end
      return {
        first_byte: first_byte, last_byte: last_byte, total_size: total_size
      }
    end
    return nil
  end

  # format a file path for a specific operating system
  # will default to unix-style paths, unless Windows OS is specified
  def self.format_path_for_os(path, os = '')
    if os =~ /Win/
      path.gsub(%r{/}, '\\')
    else
      path
    end
  end

  # handle upstream reporting/logging of errors in custom exceptions controllers
  def self.log_exception(request, params, user: nil, study: nil)
    @exception = request.env['action_dispatch.exception']
    Rails.logger.error ([@exception.message] + @exception.backtrace).join($/)
    unless static_asset_error?(@exception) # skip reporting if this is a static asset load error
      ErrorTracker.report_exception(@exception, user, params)
      MetricsService.report_error(@exception, request, user, study)
    end
  end

  # format exception JSON responses
  def self.exception_json(request)
    exception = request.env['action_dispatch.exception']
    {
      error: exception.message,
      error_class: exception.class.name,
      source: exception.backtrace&.first
    }
  end

  # determine if this is a 404 when trying to load a non-existent static asset
  def self.static_asset_error?(exception)
    exception.is_a?(ActionController::RoutingError) || /(assets|static|packs|apple-touch)/.match?(exception.message)
  end

  # Get token for client-side access to GCS bucket, depending on study privacy
  # Context: https://github.com/broadinstitute/single_cell_portal_core/pull/1747
  def self.get_read_access_token(study, user, renew: false)
    if study.present? && study.public? && ApplicationController.read_only_firecloud_client.present?
      read_only_client = ApplicationController.read_only_firecloud_client
      if !renew
        Rails.logger.info "Returning read-only service account GCS access token for public study"
        read_only_client.valid_access_token
      else
        # These read-only GCS tokens only last for 1 hour, so force refresh
        # if `renew` is true, enabling e.g. frontend to not timeout GCS bucket
        # fetches before 24-hour session expires.
        Rails.logger.info "Force-refreshing read-only service account GCS access token for public study"
        read_only_client.refresh_access_token!
      end
    elsif user.present? && user.registered_for_firecloud && study.present?
      Rails.logger.info "Returning read-only user GCS access token for private study"
      user.token_for_storage_object(study)
    else
      nil # there is no 'safe' token that will work as user has no Terra profile
    end
  end
end
