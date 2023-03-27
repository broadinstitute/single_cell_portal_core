# Be sure to restart your server when you modify this file.

# Configure sensitive parameters which will be filtered from the log file.
# update: only filter values that end with _key to preserve things like obsm_key-name, which is not a secret
Rails.application.config.filter_parameters += [
  :password, :passw, :secret, :token, /_key$/, :crypt, :salt, :certificate, :otp, :ssn
]
