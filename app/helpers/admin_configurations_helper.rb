module AdminConfigurationsHelper
  def quota_exemption_button(user)
    if user.quota_exemption?
      button_text = "<span class='fas fa-check'></span> Quota Disabled".html_safe
      button_hover = "Quota already disabled for #{user.email}"
    else
      button_text = "<span class='fas fa-ban'></span> Disable Quota".html_safe
      button_hover = "Disable download quota tracking until tomorrow for #{user.email}"
    end
    link_to button_text, grant_download_exemption_path(user.id), method: :post, class: "btn btn-xs btn-default",
            disabled: user.quota_exemption?, id: "#{user.email_as_id}-dl-exempt", title: button_hover,
            data: { toggle: 'tooltip' }
  end
end
