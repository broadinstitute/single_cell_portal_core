##
# ValidationTools
#
# Module with values for validating/santizing form & model values
module ValidationTools
  # Model Tools
  # Regex for validations

  ALPHANUMERIC_ONLY = /\A\w*\z/
  ALPHANUMERIC_DASH = /\A[\w+\-?]*\z/
  ALPHANUMERIC_PERIOD = /\A[\w+\.]+\z/ # alphanumeric plus .
  ALPHANUMERIC_SPACE_DASH = /\A[\w+\s?\-]*\z/
  NAME_CHARS = /\A[\w+\s]*\z/
  NAME_EXT_CHARS = /\A[\w+\s*[\.,]?]+\z/
  FILENAME_CHARS = /\A[\w+[\s\-\.\/\(\)]?]+\z/
  OBJECT_LABELS = /\A[\w+\s*[\-\.\/\(\)\+\,\:]?]+\z/
  # an extended regex with some slightly 'unsafe' non-word characters added in
  ALPHANUMERIC_EXTENDED = /\A[\w+\s?[\-\!\@\#\%\^\*\(\)\.\,]+]*\z/
  URL_PARAM_SAFE = /\A.*[^\"\<\>\#\%\{\}\|\\\^\~\[\]\`]\z/

  # Error messages for custom validators
  ALPHANUMERIC_ONLY_ERROR = 'contains invalid characters. Please use only alphanumeric characters.'
  ALPHANUMERIC_DASH_ERROR = 'contains invalid characters. Please use only alphanumeric characters or dashes.'
  ALPHANUMERIC_PERIOD_ERROR = 'contains invalid characters. Please use only alphanumeric or .'
  NAME_CHARS_ERROR = 'contains invalid characters. Please use only alphanumeric characters or spaces'
  NAME_EXT_CHARS_ERROR = 'contains invalid characters. Please use only alphanumeric characters, spaces, commas, or periods.'
  ALPHANUMERIC_SPACE_DASH_ERROR = 'contains invalid characters. Please use only alphanumeric characters, spaces, or dashes.'
  FILENAME_CHARS_ERROR = 'contains invalid characters. Please use only alphanumeric, spaces, or the following: - _ . / ( )'
  OBJECT_LABELS_ERROR = 'contains invalid characters. Please use only alphanumeric, spaces, or the following: - _ . / ( ) + , :'
  ALPHANUMERIC_EXTENDED_ERROR = 'contains invalid characters. Please use only alphanumeric characters, spaces, dashes, or the following: ! @ # % ( ) . ,'
  NO_SCRIPT_TAGS_ERROR = 'contains invalid characters (inline javascript).  Please remove these before continuing.'
  URL_PARAM_SAFE_ERROR = 'contains invalid characters.  Please do not use any of the following: " < > # % { } | \ ^ ~ [ ] `'
  NO_JS_FUNCTIONS_ERROR = 'contains invalid characters (javascript functions).  Please remove these before continuing.'
  # GCS tools
  GCS_HOSTNAMES = %w(storage.googleapis.com www.googleapis.com)
  SIGNED_URL_KEYS = %w(GoogleAccessId Expires Signature)
end
