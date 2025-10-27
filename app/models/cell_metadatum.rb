class CellMetadatum
  include Mongoid::Document

  # range to determine whether a group annotation is "useful" to visualize
  # an annotation must have 2-200 different groups.  only 1 label is not informative,
  # and over 200 is difficult to comprehend and slows down rendering once the group count
  # gets over a few hundred (both server- and client-side).
  GROUP_VIZ_THRESHOLD = (2..200)

  belongs_to :study
  belongs_to :study_file
  has_many :data_arrays, as: :linear_data

  field :name, type: String
  field :annotation_type, type: String
  field :values, type: Array
  field :is_differential_expression_enabled, default: false
  field :minmax_by_units, type: Hash, default: {} # for search-based minmax queries

  index({ name: 1, annotation_type: 1, study_id: 1 }, { unique: true, background: true })
  index({ study_id: 1 }, { unique: false, background: true })
  index({ study_id: 1, study_file_id: 1 }, { unique: false, background: true })

  validates_uniqueness_of :name, scope: [:study_id, :annotation_type]
  validates_presence_of :name, :annotation_type

  ##
  # INSTANCE METHODS
  ##

  # concatenate all the necessary data_array objects and construct a hash of cell names => expression values
  def cell_annotations
    cells = self.study.all_cells_array
    # replace blank/nil values with default missing label
    annot_values = AnnotationVizService.sanitize_values_array(
      self.concatenate_data_arrays(self.name, 'annotations'), self.annotation_type
    )
    Hash[cells.zip(annot_values)]
  end

  # concatenate data arrays of a given name/type in order
  def concatenate_data_arrays(array_name, array_type)
    query = {
      name: array_name, array_type: array_type, linear_data_type: 'CellMetadatum', linear_data_id: self.id,
      study_id: self.study_id, study_file_id: self.study_file_id
    }
    DataArray.concatenate_arrays(query)
  end

  # create dropdown menu value for annotation select
  def annotation_select_value
    "#{self.name}--#{self.annotation_type}--#{can_visualize? ? 'study' : 'invalid'}"
  end

  # generate a select box option for use in dropdowns that corresponds to this cell_metadatum
  def annotation_select_option
    [self.name, self.annotation_select_value]
  end

  def can_visualize?
    if self.annotation_type == 'group'
      GROUP_VIZ_THRESHOLD === self.values.count && !self.is_ontology_ids?
    else
      true
    end
  end

  # determine if there is another metadatum that represents labels that map to these IDs
  # e.g. disease vs. disease__ontology_label
  def is_ontology_ids?
    self.class.where(study_id: self.study_id, annotation_type: 'group', name: self.name + '__ontology_label').exists?
  end

  def is_ontology_labels?
    self.name.end_with?('__ontology_label')
  end

  def is_numeric?
    annotation_type == 'numeric'
  end

  # for search-based numeric metadata (e.g. organism_age), compute minmax values for each unit
  # this allows for range queries performantly
  def set_minmax_by_units!
    facet = SearchFacet.find_by(identifier: name)
    return unless is_numeric? && SearchFacet::NEED_MINMAX_BY_UNITS.include?(facet&.identifier)

    minmax_vals = {}
    # there should only ever be one unit label for a given cell metadatum
    units_meta = CellMetadatum.find_by(name: "#{name}__unit_label", annotation_type: 'group', study_id:, study_file_id:)
    return unless units_meta.present? && units_meta.values.size == 1

    unit = units_meta.values.first.pluralize
    time_units = SearchFacet::TIME_MULTIPLIERS.keys
    minmax = RequestUtils.get_minmax(cell_annotations.values)
    return unless minmax.present? && minmax.all? { |v| v.is_a?(Numeric) }

    time_units.each do |conversion_unit|
      minmax_vals[conversion_unit] = [
        facet.convert_time_between_units(
          base_value: minmax.first, original_unit: unit, new_unit: conversion_unit
        ).to_f,
        facet.convert_time_between_units(
          base_value: minmax.last, original_unit: unit, new_unit: conversion_unit
        ).to_f
      ]
    end
    update!(minmax_by_units: minmax_vals)
  end

  ##
  #
  # CLASS INSTANCE METHODS
  #
  ##

  # generate new entries based on existing StudyMetadata objects
  def self.generate_new_entries
    start_time = Time.zone.now
    arrays_created = 0
    # we only want to generate the list of 'All Cells' once per study, so do that first
    Study.all.each do |study|
      all_cells = study.all_cells
      all_cells.each_slice(DataArray::MAX_ENTRIES).with_index do |slice, index|
        cell_array = study.data_arrays.build(study_file_id: study.metadata_file.id, name: 'All Cells',
                                             cluster_name: study.metadata_file.name, array_type: 'cells',
                                             array_index: index + 1, values: slice, study_id: study.id)
        cell_array.save
      end
    end
    records = []
    StudyMetadatum.all.each do |study_metadatum|
      cell_metadatum = CellMetadatum.create(study_id: study_metadatum.study_id, study_file_id: study_metadatum.study_file_id,
                                            name: study_metadatum.name, annotation_type: study_metadatum.annotation_type,
                                            values: study_metadatum.values)
      annot_values = study_metadatum.cell_annotations.values
      annot_values.each_slice(DataArray::MAX_ENTRIES).with_index do |slice, index|
        records << {name: study_metadatum.name, cluster_name: cell_metadatum.study_file.name, array_type: 'annotations',
                    array_index: index + 1, values: slice, study_id: cell_metadatum.study_id,
                    study_file_id: cell_metadatum.study_file_id, linear_data_id: cell_metadatum.id,
                    linear_data_type: 'CellMetadatum'
        }
      end
      if records.size >= 1000
        DataArray.create(records)
        arrays_created += records.size
        records = []
      end
    end
    DataArray.create(records)
    arrays_created += records.size
    end_time = Time.zone.now
    seconds_diff = (start_time - end_time).to_i.abs

    hours = seconds_diff / 3600
    seconds_diff -= hours * 3600

    minutes = seconds_diff / 60
    seconds_diff -= minutes * 60

    seconds = seconds_diff
    msg = "Cell Metadata migration complete: generated #{self.count} new entries with #{arrays_created} child data_arrays; elapsed time: #{hours} hours, #{minutes} minutes, #{seconds} seconds"
    Rails.logger.info msg
    msg
  end
end
