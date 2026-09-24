module Api
  module V1
    class StripeController < ApiBaseController
      
      # Stripe API webhook endpoint
      # registers events from Stripe to complete purchase lifecycle and grant exemptions for study owners
      def event_webhook
        client = StripeApiClient.new
        payload = request.body.read
        event = nil
        webhook_signature = ENV['STRIPE_WEBHOOK_SECRET']

        begin
          if webhook_signature
            signature = request.env['HTTP_STRIPE_SIGNATURE']
            event = Stripe::Webhook.construct_event(
              payload, signature, webhook_signature
            )
          else
            event = Stripe::Event.construct_from(
              JSON.parse(payload, symbolize_names: true)
            )
          end
        rescue JSON::ParserError => e
          ErrorTracker.report_exception(e, nil)
          Rails.logger.error "Webhook error while parsing Stripe event request. #{e.message}"
          head 400 and return
        rescue Stripe::SignatureVerificationError => e
          ErrorTracker.report_exception(e, nil, { webhook_signature:, signature: })
          Rails.logger.error "Webhook signature verification failed. #{e.message}"
          head 400 and return
        end

        # Handle the event
        # currently we only process completed checkouts to prevent duplicate inserts from successful payment_intent events
        case event.type
        when 'checkout.session.completed', 'checkout.session.async_payment_succeeded'
          checkout_session_id = event.data.object.id
          checkout_session = client.checkout_session(checkout_session_id) # needed to get line_items expansion
          Rails.logger.info "Registering completed checkout session #{checkout_session_id}"
          purchase = Purchase.find_or_intialize_from(checkout_session)          
          purchase.payment_status = Purchase.payment_status_from(checkout_session) if purchase.persisted?
          purchase.save
        else
          Rails.logger.info "Unhandled event type: #{event.type}; skipping"
        end
        head 200
      end
    end
  end
end