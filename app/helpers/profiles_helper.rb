module ProfilesHelper
  # render an on/off toggle for inline forms on profile page
  def render_toggle(form_id, input_id, boolean_field, text_array: %w[On Off])
    toggle_state = boolean_field ? 'on' : 'off'
    toggle_text = boolean_field ? text_array.first : text_array.last
    content = "<span id='toggle_#{input_id}' class='btn btn-default user-toggle' data-form-id='#{form_id}' " \
               "data-input-id='#{input_id}' data-label-on='#{text_array.first}' data-label-off='#{text_array.last}'>" \
               "#{toggle_text} <i class='toggle-switch fa fa-fw fa-toggle-#{toggle_state}'></i></span>"
    content.html_safe
  end
end
