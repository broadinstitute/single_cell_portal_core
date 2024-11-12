module Api
  module V1
    module Concerns
      module ApiCaching
        extend ActiveSupport::Concern

        # regexes for blocker types of malicious requests
        # this prevents the app from being flooded during security scans that can cause runaway viz caching
        XSS_MATCHER = /(xssdetected|script3E)/
        SCAN_MATCHER = /(\.(git|svn|php)|NULL(%20|\+)OR(%20|\+)1|CODE_POINTS_TO_STRING|UPDATEXML|\$%7Benv)/

        # check Rails cache for JSON response based off url/params
        # cache expiration is still handled by CacheRemovalJob
        def check_api_cache!
          cache_path = RequestUtils.get_cache_path(request.path, params.to_unsafe_hash)
          if check_caching_config && Rails.cache.exist?(cache_path)
            Rails.logger.info "Reading from API cache: #{cache_path}"
            json_response = Rails.cache.fetch(cache_path)
            render json: json_response
          end
        end

        # write to the cache after a successful response
        def write_api_cache!
          cache_path = RequestUtils.get_cache_path(request.path, params.to_unsafe_hash)
          if check_caching_config && !Rails.cache.exist?(cache_path)
            Rails.logger.info "Writing to API cache: #{cache_path}"
            Rails.cache.write(cache_path, response.body)
          end
        end

        private

        # check if caching is enabled/disabled in development environment
        # will always return true in all other environments
        def check_caching_config
          if Rails.env.development?
            Rails.root.join('tmp/caching-dev.txt').exist?
          else
            true
          end
        end

        # ignore obvious malicious/bogus requests that can lead to invalid cache path entries
        def validate_cache_request
          if request.fullpath =~ XSS_MATCHER || request.fullpath =~ SCAN_MATCHER
            head 400 and return
          end
        end
      end
    end
  end
end
