# dynamic GCE instance scaling based on input file size
module ComputeScaling
  extend ActiveSupport::Concern

  # GCE machine types and file size ranges
  # produces a hash with entries like { 'n2-highmem-4' => 0..16.gigabytes }
  # change GB_PER_CORE in parent class to adjust scaling (1-8, lower numbers means more aggressive scaling)
  def scaled_machine_types
    gb_per_core = defined?(self.class::GB_PER_CORE) && self.class::GB_PER_CORE || 4
    num_cores = [4, 8, 16, 32, 48, 64]
    ram_per_core = num_cores.map { |core| (core * gb_per_core).gigabytes }.freeze
    num_cores.map.with_index do |cores, index|
      floor = index == 0 ? 0 : ram_per_core[index - 1]
      limit = index == num_cores.count - 1 ? ram_per_core[index] * 2 : ram_per_core[index]
      # ranges that use '...' exclude the given end value.
      { "n2d-highmem-#{cores}" => floor...limit }
    end.reduce({}, :merge)
  end

  # default machine_type for parameters class
  def default_machine_type
    defined?(self.class::PARAM_DEFAULTS) && self.class::PARAM_DEFAULTS[:machine_type] || scaled_machine_types.keys.first
  end

  # set machine_type based on file_size, using class defaults if specified
  def assign_machine_type
    return default_machine_type if file_size.blank?

    max_file_size = scaled_machine_types.values.last.last
    return scaled_machine_types.keys.last if file_size > max_file_size

    scaled_machine = scaled_machine_types.detect { |_, mem_range| mem_range === file_size }&.first
    scaled_machine || default_machine_type
  end
end
