# frozen_string_literal: true

# This class patches the Iyzipay API response to the authorize action
# It copies the authorization URL to a field that is recognized and persisted by Spree payments
class IyzipayAuthorizeResponsePatcher
  def initialize(response)
    @response = response
  end

  def call!
    if (url = url_for_authorization(@response)) && field_to_patch(@response).present?
      field_to_patch(@response)['message'] = url
    end

    @response
  end

  private

  def url_for_authorization(response)
    response.params["threeDSHtmlContent"]
  end

  # This field is used because the Spree code recognizes and stores it
  # This data is then used in Checkout::StripeRedirect
  def field_to_patch(response)
    response.cvv_result
  end
end