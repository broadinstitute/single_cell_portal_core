module Api
  module V1
    class StripeController < ApiBaseController
      
      # Stripe API webhook endpoint
      # registers events from Stripe to complete purchase lifecycle and grant exemptions for study owners
      def event_webhook
        client = StripeApiClient.new
        payload = request.body.read
        event = nil

        begin
          event = Stripe::Event.construct_from(
            JSON.parse(payload, symbolize_names: true)
          )
        rescue JSON::ParserError => e
          # Invalid payload
          ErrorTracker.report_exception(e, nil)
          Rails.logger.error "Webhook error while parsing Stripe event request. #{e.message}"
          head 400 and return
        end

        # Handle the event
        case event.type
        when 'checkout.session.completed', 'checkout.session.async_payment_succeeded'
          checkout_session_id = event.data.object.id
          checkout_session = client.checkout_session(checkout_session_id) # needed to get line_items expansion
          Rails.logger.info "Registering completed checkout session #{checkout_session_id}"
          purchase = Purchase.find_or_intialize_from(checkout_session)
          if purchase.persisted?
            purchase.payment_status = Purchase.payment_status_from(checkout_session)
          end
          purchase.save
        when 'payment_intent.updated', 'payment_intent.succeeded'
          payment_id = event.data.object.id
          payment_intent = client.payment_intent(payment_id)
          Rails.logger.info "Registering payment for #{payment_id}"
          purchase = Purchase.find_or_intialize_from(payment_intent)
          if purchase.persisted?
            purchase.payment_status = Purchase.payment_status_from(payment_intent)
          end
          purchase.save
        else
          Rails.logger.info "Unhandled event type: #{event.type}; skipping"
        end
        head 200
      end
    end
  end
end