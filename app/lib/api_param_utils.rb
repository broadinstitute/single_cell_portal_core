class ApiParamUtils
  def self.get_selected_annotation(params, study, cluster)
    selected_annotation = nil
    # determine which URL param to use for selection and construct base object
    selector = params[:annotation].nil? ? params[:gene_set_annotation] : params[:annotation]
    annot_name, annot_type, annot_scope = selector.nil? ? study.default_annotation.split('--') : selector.split('--')

    # construct object based on name, type & scope
    if annot_scope == 'cluster'
      selected_annotation = cluster.cell_annotations.find {|ca| ca[:name] == annot_name && ca[:type] == annot_type}
      selected_annotation[:scope] = annot_scope
    elsif annot_scope == 'user'
      # in the case of user annotations, the 'name' value that gets passed is actually the ID
      user_annotation = UserAnnotation.find(annot_name)
      selected_annotation = {name: user_annotation.name, type: annot_type, scope: annot_scope, id: annot_name}
      selected_annotation[:values] = user_annotation.values
    else
      selected_annotation = {name: annot_name, type: annot_type, scope: annot_scope}
      if annot_type == 'group'
        selected_annotation[:values] = study.cell_metadata.by_name_and_type(annot_name, annot_type).values
      else
        selected_annotation[:values] = []
      end
    end
    selected_annotation
  end

  def self.get_cluster_group(params, study)
    # determine which URL param to use for selection
    selector = params[:cluster].nil? ? params[:gene_set_cluster] : params[:cluster]
    if selector.nil? || selector.empty?
      study.default_cluster
    else
      study.cluster_groups.by_name(selector)
    end
  end
end
