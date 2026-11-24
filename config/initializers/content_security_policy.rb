# Be sure to restart your server when you modify this file.

# Define an application-wide content security policy.
# See the Securing Rails Applications Guide for more information:
# https://guides.rubyonrails.org/security.html#content-security-policy-header

# Rails.application.configure do
#   config.content_security_policy do |policy|
#     policy.default_src :self, :https
#     policy.font_src    :self, :https, :data
#     policy.img_src     :self, :https, :data
#     policy.object_src  :none
#     policy.script_src  :self, :https
#     policy.style_src   :self, :https
#     # Specify URI for violation reports
#     # policy.report_uri "/csp-violation-report-endpoint"
#   end
#
#   # Generate session nonces for permitted importmap, inline scripts, and inline styles.
#   config.content_security_policy_nonce_generator = ->(request) { request.session.id.to_s }
#   config.content_security_policy_nonce_directives = %w(script-src style-src)
#
#   # Automatically add `nonce` to `javascript_tag`, `javascript_include_tag`, and `stylesheet_link_tag`
#   # if the corresponding directives are specified in `content_security_policy_nonce_directives`.
#   # config.content_security_policy_nonce_auto = true
#
#   # Report violations without enforcing the policy.
#   # config.content_security_policy_report_only = true
# end
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
                             'https://accounts.google.com', 'https://terra-bard-dev.appspot.com', 'https://terra-bard-alpha.appspot.com', 'https://terra-bard-prod.appspot.com',
                             'https://rest.ensembl.org', 'https://eutils.ncbi.nlm.nih.gov', 'https://mygene.info', 'https://webservice.wikipathways.org', 'https://o54426.ingest.sentry.io',
                             'https://igv-genepattern-org.s3.amazonaws.com', 'https://*.soe.ucsc.edu', 'https://raw.githubusercontent.com', 'https://www.ebi.ac.uk'
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

  config.csp = {
    # "meta" values. these will shape the header, but the values are not included in the header.
    preserve_schemes: true, # default: false. Schemes are removed from host sources to save bytes and discourage mixed content.

    base_uri: %w('self'),
    # directive values: these values will directly translate into source directives
    default_src: %w('self'),
    frame_src: %w('self'), # if child-src isn't supported, the value for frame-src will be set.
    font_src: %w('self' data: https://fonts.googleapis.com https://fonts.google.com https://fonts.gstatic.com ),
    form_action: %w('self' https://accounts.google.com),
    connect_src: allowed_connect_sources,
    img_src: %w('self' data: blob: https://www.google-analytics.com https://online.swagger.io res.cloudinary.com twemoji.maxcdn.com),
    manifest_src: %w('self'),
    object_src: %w('none'),
    worker_src: %w('self' blob:),
    script_src: %w('self' blob: 'unsafe-eval' 'unsafe-inline' 'strict-dynamic' https://cdn.plot.ly https://cdn.datatables.net
                     https://www.google-analytics.com https://cdnjs.cloudflare.com https://maxcdn.bootstrapcdn.com
                     https://use.fontawesome.com https://js-agent.newrelic.com https://bam.nr-data.net
                     https://*.soe.ucsc.edu),
    style_src: %w('self' blob: https://maxcdn.bootstrapcdn.com https://fonts.googleapis.com https://fonts.google.com 'unsafe-inline'),
    upgrade_insecure_requests: true # see https://www.w3.org/TR/upgrade-insecure-requests/
  }

end
