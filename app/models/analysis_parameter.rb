class AnalysisParameter
  include Mongoid::Document
  extend ValidationTools
  extend ErrorTracker

  belongs_to :analysis_configuration
  has_many :analysis_parameter_filters, dependent: :delete_all
  accepts_nested_attributes_for :analysis_parameter_filters, allow_destroy: :true
  has_many :analysis_output_associations, dependent: :delete_all
  accepts_nested_attributes_for :analysis_output_associations, allow_destroy: :true

  field :data_type, type: String # input, output
  field :call_name, type: String # name of WDL task this input
  field :parameter_type, type: String # type of the parameter (from primitive/compound types)
  field :parameter_name, type: String # name of the parameter from the WDL
  field :parameter_value, type: String, default: '' # value of the parameter (optional)
  field :description, type: String # help text for input (optional, user-supplied)
  field :optional, type: Boolean, default: false # parameter optional?
  field :associated_model, type: String # SCP model this parameter is associated with, if any (e.g. StudyFile, etc)
  field :associated_model_method, type: String # model instance method that should be called to set value by
  field :associated_model_display_method, type: String # model instance method that should be called to set DISPLAY value by (for dropdowns)
  field :association_filter_attribute, type: String # attribute to filter instances of :associated_model by (e.g. file_type)
  field :association_filter_value, type: String # attribute value to use in above filter (e.g. Expresion Matrix)
  field :output_file_type, type: String # StudyFile#file_type of output files
  field :visible, type: Boolean, default: proc { !optional } # default to true if input is required
  field :apply_to_all, type: Boolean, default: false # whether or not to apply :associated_model_method to all instances (if an array type input)
  field :is_reference_bundle, type: Boolean, default: false # whether or not this input is for a reference genome

  DATA_TYPES = %w(inputs outputs)
  PRIMITIVE_PARAMETER_TYPES = %w(String Int Float File Boolean String? Int? Float? File? Boolean?)
  COMPOUND_PARAMETER_TYPES = %w(Array Map Object)
  ASSOCIATED_MODELS = %w(Study StudyFile Taxon GenomeAssembly GenomeAnnotation ClusterGroup CellMetadatum)
  ASSOCIATED_MODEL_ATTR_NAMES = [:ASSOCIATED_MODEL_METHOD, :ASSOCIATED_MODEL_DISPLAY_METHOD, :OUTPUT_ASSOCIATION_ATTRIBUTE]

  validates_presence_of :data_type, :call_name, :parameter_type, :parameter_name
  validates_presence_of :associated_model_method, :associated_model_display_method, on: :update,
                        if: proc {|attributes| attributes.associated_model.present?}
  validates_format_of :parameter_name, with: ValidationTools::ALPHANUMERIC_PERIOD,
                      message: ValidationTools::ALPHANUMERIC_PERIOD_ERROR
  validates_format_of :call_name, with: ValidationTools::FILENAME_CHARS, message: ValidationTools::FILENAME_CHARS_ERROR
  validates_uniqueness_of :parameter_name, scope: [:data_type, :call_name, :analysis_configuration_id]
  validates_inclusion_of :data_type, in: DATA_TYPES
  validate :validate_parameter_type
  validate :validate_parameter_value_by_type, unless: proc {|attributes| attributes.parameter_value.blank?}
  validate :validate_output_file_type, on: :update, if: proc {|attributes| attributes.data_type == 'outputs'}
  validates_uniqueness_of :is_reference_bundle, scope: :analysis_configuration_id, if: proc {|attributes| attributes.is_reference_bundle}

  # validations for filters as they live in the same form
  validate do |analysis_parameter|
    analysis_parameter.analysis_parameter_filters.each do |filter|
      next if filter.valid?
      filter.errors.full_messages.each do |msg|
        errors.add(:base, "Filter Error - #{msg}")
      end
    end
  end

  # get the call & parameter name together for use in Methods Repository configuration objects
  def config_param_name
    "#{self.call_name}.#{self.parameter_name}"
  end

  # determine if parameter is an array type
  def is_array?
    self.parameter_type.split('[').first == 'Array'
  end

  # determine if values need to be scoped by a study or not
  def study_scoped?
    if self.associated_model.present?
      self.associated_model == "Study" || self.associated_model_class.method_defined?(:study_id)
    else
      false
    end
  end

  # check if this is an output file parameter
  def is_output_file?
    self.data_type == 'outputs' && self.parameter_type.match(/File/).present?
  end

  # type of input parameter for array-based inputs
  def array_type
    if self.is_array?
      self.parameter_type.split('[').last.split(']').first
    else
      nil
    end
  end

  # helper to return input type method name
  def input_type
    if self.associated_model.present? || self.is_array?
      :select
    else
      case self.parameter_type
      when /String/
        :text_field
      when /File/
        :text_field
      when /Int/
        :number_field
      when /Float/
        :number_field
      when /Boolean/
        :boolean_select
      end
    end
  end

  # helper to return the correct method for setting
  def value_method_type
    if self.associated_model.present? || self.parameter_type == 'File' || self.is_array?
      :options_for_select
    else
      :value
    end
  end

  # helper to format a user-supplied value based in parameter type
  def formatted_user_value(value)
    if value.blank?
      ''
    else
      case self.parameter_type
      when /String/
        !value.start_with?('"') ? "\"#{value}\"" : value
      when /Boolean/
        "#{value.downcase.to_s == 'true'}"
      else
        value
      end
    end
  end

  # helper to constantize the associated_model
  def associated_model_class
    self.associated_model.present? ? self.associated_model.constantize : nil
  end

  # used to populate dropdowns in analysis_parameter_form, not for use with user inputs
  # see options_by_association_method for user forms
  def admin_options(attribute)
    if self.associated_model.present?
      model = self.associated_model_class
      const_name = attribute.upcase
      model.const_defined?(const_name) ? model.const_get(const_name) : []
    else
      []
    end
  end

  # return array of options for select when rendering a user input form
  def options_by_association_method(study=nil)
    if self.associated_model_class.present?
      instances = get_instances_by_associations(study)
      self.analysis_parameter_filters.each do |filter|
        if filter.multiple?
          instances = instances.where(filter.attribute_name.to_sym.in => filter.multiple_values)
        else
          instances = instances.where(filter.attribute_name.to_sym => "#{filter.value}")
        end
      end
      if self.association_filter_attribute.present? && self.association_filter_value.present?
        instances = instances.where(self.association_filter_attribute.to_sym => "#{self.association_filter_value}")
      end
      instances.map {|instance| [instance.send(self.associated_model_display_method), "\"#{instance.send(self.associated_model_method)}\""]}
    else
      []
    end
  end

  private

  def get_instances_by_associations(study)
    model = self.associated_model_class
    instances = []
    if model == Study
      # we already have the instance if the associated model is a Study
      instances = model.where(id: study.id)
    elsif model != Study && study.present?
      instances = model.where(study_id: study.id)
    elsif model != StudyFile
      instances = model.all
    end
    instances
  end

  # ensure parameter type conforms to WDL input types
  def validate_parameter_type
    if PRIMITIVE_PARAMETER_TYPES.include? self.parameter_type || self.parameter_type === 'Object'
      true
    elsif self.parameter_type.include?('[') # compound types have brackets []
      # extract primitives from complex type
      raw_primitives = self.parameter_type.split('[').last
      raw_primitives.gsub!(/]\??/, '')
      primitives = raw_primitives.split(',').map(&:strip)
      if self.parameter_type.start_with?('Array')
        # there is only one primitive type from the control list
        unless primitives.size === 1 && PRIMITIVE_PARAMETER_TYPES.include?(primitives.first)
          errors.add(:parameter_type, "has an invalid primitive type: #{(primitives - PRIMITIVE_PARAMETER_TYPES).join(', ')}")
        end
      elsif self.parameter_type.start_with?('Map')
        # there are two primitive types, and the intersection is the same as the unique list of primitives
        unless primitives.size === 2 && (primitives & PRIMITIVE_PARAMETER_TYPES === primitives.uniq)
          errors.add(:parameter_type, "has an invalid primitive type: #{(primitives - PRIMITIVE_PARAMETER_TYPES).join(', ')}")
        end
      else
        errors.add(:parameter_type, "has an invalid complex type: #{self.parameter_type.split('[').first}")
      end
    else
      errors.add(:parameter_type, "has an invalid value: #{self.parameter_type}")
    end
  end

  # validate parameter values depending on their type
  def validate_parameter_value_by_type
    has_validation_error = false
    case self.parameter_type
    when 'String'
      unless self.parameter_value.start_with?('"') && self.parameter_value.end_with?('"')
        has_validation_error = true
      end
    when 'Int'
      unless self.parameter_value.is_a?(Integer)
        has_validation_error = true
      end
    when 'Float'
      unless self.parameter_value.is_a?(Float)
        has_validation_error = true
      end
    when 'File'
      unless self.parameter_value.start_with?('"gs://')
        has_validation_error = true
      end
    else
      true # complex data types are too complicated to validate, so punt
    end
    if has_validation_error
      errors.add(:parameter_value, "is not a valid #{self.parameter_type} value: #{self.parameter_value}.")
    end
  end

  def validate_output_file_type
    if self.is_output_file?
      unless StudyFile::STUDY_FILE_TYPES.include?(self.output_file_type)
        errors.add(:output_file_type, "'#{self.output_file_type}' is not a valid file type: #{StudyFile::STUDY_FILE_TYPES.join(', ')}")
      end
    end
  end
end
