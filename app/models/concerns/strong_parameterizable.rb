# frozen_string_literal: true
#
# strong_parameterizable.rb - module for auto-generating strong parameter arrays based off model attributes/fields
module StrongParameterizable
  extend ActiveSupport::Concern
  # attributes that should never be mass assigned
  PROTECTED_ATTRIBUTES = %w[created_at updated_at].freeze

  # list of classes that extend this module (not include - means methods are available at class level)
  #
  # * *returns*
  #   - (Array<Class>)
  def self.extended_classes
    Rails.application.eager_load! if Rails.env.development? || Rails.env.test?

    Mongoid.models.select { |model| model.is_a?(StrongParameterizable) }
  end

  # array of parameter names allowed for mass assignment
  # includes nested objects via accepts_nested_attributes_for or embeds_(one/many)
  #
  # * *params*
  #   - +klass+ (Class) => defined class
  #
  # * *returns*
  #   - (Array<Symbol, Hash>)
  def strong_parameters(klass = nil)
    ref = klass || self
    param_list = []
    if ref.included_modules.include?(Mongoid::Document)
      param_list += params_from_fields(ref)
    elsif ref.respond_to?(:new) && ref.new.respond_to?(:attributes)
      param_list += params_from_attrs(ref)
    end
    if ref.respond_to?(:nested_attributes)
      ref.nested_attributes.keys.each do |association|
        assoc_name = association.to_s.chomp('_attributes')
        const_name = assoc_name.singularize.camelize
        param_list << { association.to_sym => strong_parameters(const_name.constantize) } if defined? const_name
      end
    end
    param_list
  end

  # get parameter names from attributes hash
  #
  # * *params*
  #   - +klass+ (Class) => defined class that responds to both :new and :attributes
  #
  # * *returns*
  #   - (Array<Symbol>)
  def params_from_attrs(klass)
    klass.new.attributes.keys.reject { |key| PROTECTED_ATTRIBUTES.include?(key) }
  end

  # get parameters from Mongoid::Field entries
  #
  # * *params*
  #   - +klass+ (Class) => defined class that includes the Mongoid::Document module
  #
  # * *returns*
  #   - (Array<Symbol, Hash>)
  def params_from_fields(klass)
    klass.fields.reject { |name, _| PROTECTED_ATTRIBUTES.include?(name) }.map { |_, field| get_field_definition(field) }
  end

  # return param definition for Mongoid::Field
  # will either be symbol for field name or hash of name to nested attributes or data type
  # examples:
  #   :name
  #   { :raw_counts_associations=>[] }
  #   { :cluster_file_info_attributes=>[:_id, :custom_colors, :annotation_split_defaults] }
  #
  # * *params*
  #   - +field+ (Mongoid::Field) => Mongoid field as defined via the :field method in parent class
  #
  # * *returns*
  #   - (Symbol, Hash)
  def get_field_definition(field)
    data_type = field.options[:type]
    data_type.ancestors.include?(Enumerable) ? { field.name.to_sym => data_type.new } : field.name.to_sym
  end
end
