# getters/setters for annotations in differential expression UX
module Annotatable
  extend ActiveSupport::Concern

  # retrieve source annotation object
  def annotation_object
    case annotation_scope
    when 'study'
      study.cell_metadata.by_name_and_type(annotation_name, 'group')
    when 'cluster'
      cluster_group.cell_annotations.detect do |annotation|
        annotation[:name] == annotation_name && annotation[:type] == 'group'
      end
    end
  end

  # get query string formatted annotation identifier, e.g. cell_type__ontology_label--group--study
  def annotation_identifier
    case annotation_scope
    when 'study'
      annotation_object.annotation_select_value
    when 'cluster'
      cluster_group.annotation_select_value(annotation_object)
    end
  end

  # validation for ensuring annotation object is found
  def annotation_exists?
    if annotation_object.blank?
      errors.add(:base, "Annotation: #{annotation_name} (#{annotation_scope}) not found")
    end
  end

  # return a parsed instance from a parent study_file_id, e.g. ClusterGroup
  def instance_from_study_file_id(study_file_id, associated_class)
    return nil if study_file_id.blank?

    study_file_id = StudyFile.find(study_file_id).id
    associated_class.send(:find_by, { study_file_id: })
  end
end
