require 'iyzipay_authorize_response_patcher'

module Spree
  class Gateway
    class IyzipayAga < Spree::Gateway
      acts_as_taggable
      preference :enterprise_id, :integer

      def supports?(source)
        true
      end

      def provider_class
        require 'active_merchant/billing/gateways/iyzipay_payment'
        ActiveMerchant::Billing::IyzipayPaymentGateway
      end

      def payment_profiles_supported?
        true
      end

      def method_type
        'iyzipay'
      end

      # NOTE: the name of this method is determined by Spree::Payment::Processing
      def purchase(money, creditcard, gateway_options)
        Rails.logger.error("IyzipayAga.purchase(money: #{money}, creditcard: #{creditcard}, gateway_options: #{gateway_options})")
        provider.capture(money, creditcard, gateway_options)
      end

      # NOTE: the name of this method is determined by Spree::Payment::Processing
      def authorize(money, creditcard, gateway_options)
        Rails.logger.error("IyzipayAga.authorize(money: #{money}, creditcard: #{creditcard}, gateway_options: #{gateway_options})")
        authorize_response = provider.authorize(money, creditcard, gateway_options)
        IyzipayAuthorizeResponsePatcher.new(authorize_response).call!
      rescue
        failed_activemerchant_billing_response($!.message)
      end

      # NOTE: the name of this method is determined by Spree::Payment::Processing
      def void(response_code, _creditcard, gateway_options)
        gateway_options[:stripe_account] = stripe_account_id
        provider.void(response_code, gateway_options)
      end

      # NOTE: the name of this method is determined by Spree::Payment::Processing
      def credit(money, _creditcard, response_code, gateway_options)
        Rails.logger.error("IyzipayAga.credit(money: #{money}, _creditcard: #{_creditcard}, gateway_options: #{gateway_options})")
        gateway_options[:stripe_account] = stripe_account_id
        provider.refund(money, response_code, gateway_options)
      end

      def create_profile(payment)
        return unless payment.source.gateway_customer_profile_id.nil?

        profile_storer = Stripe::ProfileStorer.new(payment, provider)
        profile_storer.create_customer_from_token
      end

      private

      def failed_activemerchant_billing_response(error_message)
        ActiveMerchant::Billing::Response.new(false, error_message)
      end
    end
  end
end
