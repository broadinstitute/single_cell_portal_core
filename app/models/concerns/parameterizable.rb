# handle converting ActiveModel attributes into a command line string
# used in PAPI jobs via PapiClient and IngestJob
module Parameterizable
  extend ActiveSupport::Concern

  # regular expression to validate GS url format
  GS_URL_REGEXP = %r{\Ags://}

  # regular expression to match GCR URI format
  # faster than checking repository for image presence, has no upstream dependencies
  # format as gcr.io/google-project/docker-image:version
  # google-project: 6-30 alphanumeric characters, plus dash (-)
  # docker-image: 4-128 alphanumeric characters, plus dash (-) and periods (.)
  # version: standard semantic versioning (x.y.z), plus extra alphanumerics after last digit for commit SHA
  GCR_URI_REGEXP = %r{gcr.io/[\w-]{6,30}/[\w.-]{4,128}+:\d+\.\d+\.\d+\w*}

  # acceptable Google N-machine types
  # https://cloud.google.com/compute/docs/general-purpose-machines
  GCE_MACHINE_TYPES = %w[n1 n2].map do |family|
    %w[standard highmem highcpu].map do |series|
      [2, 4, 8, 16, 32, 64, 96].map do |cores|
        [family, series, cores].join('-')
      end
    end
  end.flatten.freeze

  # convert attribute name into CLI-formatted option
  def self.to_cli_opt(param_name)
    "--#{param_name.to_s.gsub(/_/, '-')}"
  end

  # return array of all initialized attributes as CLI arguments, e.g. annotation_name => --annotation-name
  # will also append PARAMETER_NAME at the end as defined by including class
  def to_options_array
    options_array = []
    attributes.each do |attr_name, value|
      next if value.blank?

      # explicit check for == true to flag-only options that have no value, like --extract "['cluster', 'metadata']"
      if value == true
        options_array << Parameterizable.to_cli_opt(attr_name)
      else
        options_array += [Parameterizable.to_cli_opt(attr_name), value.to_s]
      end
    end
    options_array << self.class::PARAMETER_NAME if defined? self.class::PARAMETER_NAME
    options_array
  end

  # name of ingest action
  # example: RenderExpressionArraysParameters => :render_expression_arrays
  def action_name
    self.class.name.gsub(/Parameters/, '').underscore.to_sym
  end
end
