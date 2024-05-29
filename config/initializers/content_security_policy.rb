# Be sure to restart your server when you modify this file.

# Define an application-wide content security policy
# For further information see the following documentation
# https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Content-Security-Policy

# Rails.application.config.content_security_policy do |policy|
#   policy.default_src :self, :https
#   policy.font_src    :self, :https, :data
#   policy.img_src     :self, :https, :data
#   policy.object_src  :none
#   policy.script_src  :self, :https
    # Allow @vite/client to hot reload javascript changes in development
#    policy.script_src *policy.script_src, :unsafe_eval, "http://#{ ViteRuby.config.host_with_port }" if Rails.env.development?

    # You may need to enable this in production as well depending on your setup.
#    policy.script_src *policy.script_src, :blob if Rails.env.test?

#   policy.style_src   :self, :https
    # Allow @vite/client to hot reload style changes in development
#    policy.style_src *policy.style_src, :unsafe_inline if Rails.env.development?

#   # If you are using webpack-dev-server then specify webpack-dev-server host
#   policy.connect_src :self, :https, "http://localhost:3035", "ws://localhost:3035" if Rails.env.development?
    # Allow @vite/client to hot reload changes in development
#    policy.connect_src *policy.connect_src, "ws://#{ ViteRuby.config.host_with_port }" if Rails.env.development?


#   # Specify URI for violation reports
#   # policy.report_uri "/csp-violation-report-endpoint"
# end

# If you are using UJS then enable automatic nonce generation
# Rails.application.config.content_security_policy_nonce_generator = -> request { SecureRandom.base64(16) }

# Set the nonce only to specific directives
# Rails.application.config.content_security_policy_nonce_directives = %w(script-src)

# Report CSP violations to a specified URI
# For further information see the following documentation:
# https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Content-Security-Policy-Report-Only
# Rails.application.config.content_security_policy_report_only = true

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
                             'https://www.googleapis.com', 'https://storage.googleapis.com', 'https://s3.amazonaws.com', 'https://data.broadinstitute.org', 'https://portals.broadinstitute.org',
                             'https://us.input.tcell.insight.rapid7.com', 'https://api.tcell.io', 'https://us.browser.tcell.insight.rapid7.com',
                             'https://us.agent.tcell.insight.rapid7.com', 'https://us.jsagent.tcell.insight.rapid7.com', 'https://accounts.google.com',
                             'https://terra-bard-dev.appspot.com', 'https://terra-bard-alpha.appspot.com', 'https://terra-bard-prod.appspot.com',
                             'https://rest.ensembl.org', 'https://eutils.ncbi.nlm.nih.gov', 'https://mygene.info', 'https://webservice.wikipathways.org', 'https://o54426.ingest.sentry.io',
                             'https://igv-genepattern-org.s3.amazonaws.com', 'https://*.soe.ucsc.edu'
                            ]
  if ENV['NOT_DOCKERIZED']
    # enable connections to live reload server
    allowed_connect_sources.push('https://localhost:3035')
    allowed_connect_sources.push('wss://localhost:3035')
    # 3036 is the Vite reload server
    allowed_connect_sources.push('wss://localhost:3036')
    allowed_connect_sources.push('ws://localhost:3036')
    allowed_connect_sources.push('ws://127.0.0.1:3036')
  end
  # For appcues
  allowed_connect_sources.push('https://*.appcues.com')
  allowed_connect_sources.push('https://*.appcues.net')
  allowed_connect_sources.push('wss://*.appcues.net')
  allowed_connect_sources.push('wss://*.appcues.com')
  config.csp = {
    # "meta" values. these will shape the header, but the values are not included in the header.
    preserve_schemes: true, # default: false. Schemes are removed from host sources to save bytes and discourage mixed content.

    base_uri: %w('self'),
    # directive values: these values will directly translate into source directives
    default_src: %w('self'),
    block_all_mixed_content: true, # see http://www.w3.org/TR/mixed-content/
    frame_src: %w('self' https://us.input.tcell.insight.rapid7.com https://us.browser.tcell.insight.rapid7.com https://*.appcues.com
                     https://us.agent.tcell.insight.rapid7.com), # if child-src isn't supported, the value for frame-src will be set.
    font_src: %w('self' data: https://fonts.googleapis.com https://fonts.google.com https://fonts.gstatic.com ),
    form_action: %w('self' https://accounts.google.com),
    connect_src: allowed_connect_sources,
    img_src: %w('self' data: blob: https://www.google-analytics.com https://online.swagger.io res.cloudinary.com twemoji.maxcdn.com),
    manifest_src: %w('self'),
    object_src: %w('none'),
    script_src: %w('self' blob: 'unsafe-eval' 'unsafe-inline' 'strict-dynamic' https://cdn.plot.ly https://cdn.datatables.net
                     https://www.google-analytics.com https://cdnjs.cloudflare.com https://maxcdn.bootstrapcdn.com
                     https://use.fontawesome.com https://api.tcell.io https://us.browser.tcell.insight.rapid7.com
                     https://us.jsagent.tcell.insight.rapid7.com https://us.agent.tcell.insight.rapid7.com https://js-agent.newrelic.com
                     https://bam.nr-data.net https://*.appcues.com https://*.appcues.net https://*.soe.ucsc.edu),
    style_src: %w('self' blob: https://maxcdn.bootstrapcdn.com
                      https://*.appcues.com https://*.appcues.net https://fonts.googleapis.com https://fonts.google.com 'unsafe-inline'),
    upgrade_insecure_requests: true # see https://www.w3.org/TR/upgrade-insecure-requests/
  }

end
