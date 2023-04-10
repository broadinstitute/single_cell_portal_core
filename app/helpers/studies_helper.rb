module StudiesHelper
  # formatted label for boolean values
  def get_boolean_label(field)
    if field.nil?
      "<span class='label label-default'>N/A</span>".html_safe
    else
      field ? "<span class='fas fa-check text-success'></span>".html_safe : "<span class='fas fa-times text-danger'></span>".html_safe
    end
  end

  # formatted label for parse status of uploaded files
  def get_parse_label(parse_status)
    case parse_status
      when 'unparsed'
        "<span class='fas fa-times text-danger' title='Unparsed' data-toggle='tooltip'></span>".html_safe
      when 'parsing'
        "<span class='fas fa-sync-alt text-warning' title='Parsing' data-toggle='tooltip'></span>".html_safe
      when 'parsed'
        "<span class='fas fa-check text-success' title='Parsed' data-toggle='tooltip'></span>".html_safe
      else
        "<span class='fas fa-times text-danger' title='Unparsed' data-toggle='tooltip'></span>".html_safe
    end
  end

  # formatted label for NA values
  def get_na_label
    "<span class='label label-default'><i class='fas fa-ban' aria-hidden='true'></i> N/A</span>".html_safe
  end

  # return formatted path with parameters for main site_path url
  def get_site_path_with_params(search_val, order_val)
    if search_val.blank?
      site_path(order: order_val)
    else
      site_path(order: order_val, search_terms: search_val)
    end
  end

  def get_convention_label
    "<span class='fas fa-copyright text-muted' aria-hidden='true' title='Convention Metadata' data-toggle='tooltip'></span>".html_safe
  end

  # get either a count of values for group annotations, or bounds for numeric annotations
  def get_annotation_bounds(values:, annotation_type:)
    case annotation_type.to_sym
    when :group
      values.any? ? values.size : '> 200'
    when :numeric
      RequestUtils.get_minmax(values).join(', ')
    end
  end

  # helper for displaying sorted, unique values from a given group annotation
  # if there are too many values (> 100), then only a count is displayed
  # does not return anything for numeric annotations
  def get_sorted_group_values(values:, annotation_type:)
    if annotation_type.to_sym == :group
      if CellMetadatum::GROUP_VIZ_THRESHOLD === values.size || values.size == 1
        Naturally.sort(values).join(', ')
      else
        label = "<big><span class='label label-warning' data-toggle='tooltip' " + \
        "title='Group-based annotations with over 200 groups are not visualized for performance reasons'>" + \
        "<i class='fas fa-exclamation-triangle'></i> List too long, will not visualize</span></big>"
        label.html_safe
      end
    end
  end
end
