# frozen_string_literal: true

# Provides the redirect path if a redirect to the payment gateway is needed
module Checkout
  class IyzipayRedirect
    def initialize(params, order)
      @params = params
      @order = order
    end

    # Returns the path to the authentication form if a redirect is needed
    def path
      return unless iyzipay_payment_method?

      payment = OrderManagement::Subscriptions::IyzipayPaymentAuthorize.new(@order).call!
      raise if @order.errors.any?

      field_with_url(payment) # if url?(field_with_url(payment))
    end

    private

    def iyzipay_payment_method?
      return unless @params[:order][:payments_attributes]

      payment_method_id = @params[:order][:payments_attributes].first[:payment_method_id]
      payment_method = Spree::PaymentMethod.find(payment_method_id)
      payment_method.is_a?(Spree::Gateway::Iyzipay)
    end

    def url?(string)
      return false if string.blank?

      string.starts_with?("http")
    end

    # Iyzipay::AuthorizeResponsePatcher patches the Iyzipay authorization response
    #   so that this field stores the redirect URL
    def field_with_url(payment)
      Base64.decode64(payment.cvv_response_message)
    end
  end
end
