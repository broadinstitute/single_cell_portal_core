# main handler for storage service operations using vendor-specific clients
class StorageService
  extend ServiceAccountManager
  extend Loggable

  # API clients that can use StorageService
  ALLOWED_CLIENTS = [StorageProvider::Gcs].freeze

  # generic handler to call an underlying client method and forward all positional/keyword params
  #
  # * *params*
  #   - +client+ (Object) => any API client from ALLOWED_CLIENTS
  #   - +client_method+ (String, Symbol) => underlying client method to invoke
  #   - +...+ (Multiple) => any positional or keyword parameters for client_method
  #
  # * *returns*
  #   - (Multiple) => return from client_method
  def self.call_client(client, client_method, ...)
    unless ALLOWED_CLIENTS.map(&:to_s).include?(client.class.name)
      raise ArgumentError, "#{client.class} not one of allowed clients: #{ALLOWED_CLIENTS.join(', ')}"
    end

    client.send(client_method, ...)
  end

  def self.create_study_bucket(client, study)
    bucket_id = study.bucket_id
    call_client(client, :create_study_bucket, bucket_id)
    call_client(client, :enable_bucket_autoclass)
    call_client(client, :update_bucket_acl, bucket_id, study.user, :writer)
    study.study_shares.each do |share|
      role = share.permission == 'Edit' ? :writer : :reader
      call_client(client, :enable_bucket_autoclass, bucket_id, share.email, role)
    end
  end
end
