# dynamic GCE instance scaling based on input file size
module ComputeScaling
  extend ActiveSupport::Concern

  # default for maximum number of cores allowed
  MAX_MACHINE_CORES = 64

  # GCE machine types and file size ranges
  # produces a hash with entries like { 'n2-highmem-4' => 0..16.gigabytes }
  # change RAM_SCALING in parent class to adjust scaling (1-8, lower number means faster scaling relative to file size)
  def scaled_machine_types
    gb_per_core = defined?(self.class::RAM_SCALING) && self.class::RAM_SCALING || 4
    num_cores = [4, 8, 16, 32, 48, 64].keep_if { |cores| cores <= self.class::MAX_MACHINE_CORES }
    ram_per_core = num_cores.map { |core| (core * gb_per_core).gigabytes }
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

  # find the next largest machine to use for an ingest process
  def next_machine_type
    machine_names = scaled_machine_types.keys
    # nil return used as escape clause for stopping retries after largest machine fails
    return nil if machine_type == machine_names.last

    current_machine_idx = machine_names.index(machine_type)
    machine_names[current_machine_idx + 1]
  end
end
