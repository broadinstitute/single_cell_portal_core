# Be sure to restart your server when you modify this file.

# Define an application-wide content security policy
# For further information see the following documentation
# https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Content-Security-Policy

SecureHeaders::Configuration.default do |config|
  config.cookies = {
      secure: true # mark all cookies as "Secure"
  }
  # Add "; preload" and submit the site to hstspreload.org for best protection.
  config.hsts = "max-age=15768000; includeSubdomains; preload"
  config.x_frame_options = "SAMEORIGIN"
  config.x_content_type_options = "nosniff"
  config.x_xss_protection = "1; mode=block"
  config.x_permitted_cross_domain_policies = "none"
  config.x_download_options = "noopen"
  config.referrer_policy = %w(origin-when-cross-origin strict-origin-when-cross-origin)
  allowed_connect_sources = ['\'self\'', "https://#{ENV['HOSTNAME']}", 'https://www.google-analytics.com', 'https://cdn.jsdelivr.net', 'https://igv.org',
                    'https://www.googleapis.com', 'https://s3.amazonaws.com', 'https://data.broadinstitute.org', 'https://portals.broadinstitute.org',
                    'https://us.input.tcell.insight.rapid7.com', 'https://api.tcell.io', 'https://us.browser.tcell.insight.rapid7.com',
                    'https://us.agent.tcell.insight.rapid7.com', 'https://us.jsagent.tcell.insight.rapid7.com', 'https://accounts.google.com',
                    'https://bam.nr-data.net', 'https://terra-bard-dev.appspot.com', 'https://terra-bard-alpha.appspot.com',
                    'https://terra-bard-prod.appspot.com', 'https://rest.ensembl.org', 'https://eutils.ncbi.nlm.nih.gov', 'https://mygene.info',
                    'https://webservice.wikipathways.org']
  if ENV['NOT_DOCKERIZED']
    # enable connections to live reload server
    allowed_connect_sources.push('https://localhost:3035')
    allowed_connect_sources.push('wss://localhost:3035')
  end
  config.csp = {
      # "meta" values. these will shape the header, but the values are not included in the header.
      preserve_schemes: true, # default: false. Schemes are removed from host sources to save bytes and discourage mixed content.

      base_uri: %w('self'),
      # directive values: these values will directly translate into source directives
      default_src: %w('self'),
      block_all_mixed_content: true, # see http://www.w3.org/TR/mixed-content/
      frame_src: %w('self' https://us.input.tcell.insight.rapid7.com https://us.browser.tcell.insight.rapid7.com
                     https://us.agent.tcell.insight.rapid7.com), # if child-src isn't supported, the value for frame-src will be set.
      font_src: %w('self' data:),
      form_action: %w('self' https://accounts.google.com),
      connect_src: allowed_connect_sources,
      img_src: %w('self' data: blob: https://www.google-analytics.com https://online.swagger.io),
      manifest_src: %w('self'),
      object_src: %w('none'),
      script_src: %w('self' blob: 'unsafe-eval' 'unsafe-inline' 'strict-dynamic' https://cdn.plot.ly https://cdn.datatables.net
                     https://www.google-analytics.com https://cdnjs.cloudflare.com https://maxcdn.bootstrapcdn.com
                     https://use.fontawesome.com https://api.tcell.io https://us.browser.tcell.insight.rapid7.com
                     https://us.jsagent.tcell.insight.rapid7.com https://us.agent.tcell.insight.rapid7.com https://js-agent.newrelic.com
                     https://bam.nr-data.net),
      style_src: %w('self' blob: https://maxcdn.bootstrapcdn.com 'unsafe-inline'),
      upgrade_insecure_requests: true, # see https://www.w3.org/TR/upgrade-insecure-requests/
  }

end
