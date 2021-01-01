# frozen_string_literal: true

module ActiveMerchant
  module Billing
    class IyzipayPaymentGateway < Spree::Gateway
      self.test_url = 'https://sandbox-api.iyzipay.com'
      self.live_url = 'https://api.iyzipay.com'

      self.supported_countries = ['TR']
      self.default_currency = 'TR'
      self.supported_cardtypes = [:visa, :master, :american_express]

      self.homepage_url = 'https://www.iyzico.com/'
      self.display_name = 'Iyzipay'
      self.logger = ::Rails.logger

      STANDARD_ERROR_CODE_MAPPING = {}

      def initialize(options={})
        require "iyzipay"

        super
      end

      def iyzipay_options
        opts = Iyzipay::Options.new
        opts.api_key = ENV.fetch('IYZIPAY_API_KEY')
        opts.secret_key = ENV.fetch('IYZIPAY_SECRET')
        opts.base_url = "https://api.iyzipay.com"
        opts
      end

      def capture(money, creditcard, gateway_options)
        payment = fetch_payment(gateway_options)

        initialize3ds_response = JSON.parse(payment.cvv_response_message)
        if initialize3ds_response["status"] == "failure"
          return Response.new(false, message_from_transaction_result(initialize3ds_response), initialize3ds_response, response_options(initialize3ds_response))
        end

        request = {
          conversationId: initialize3ds_response['conversationId'],
          paymentId: initialize3ds_response['paymentId'],
        }

        if initialize3ds_response['conversationData'].present?
          request[:conversationData] = initialize3ds_response['conversationData']
        end
        response = Iyzipay::Model::ThreedsPayment.new.create(request, iyzipay_options)
        payment.cvv_response_message = response

        response = JSON.parse response

        if response["status"] == 'success'
          approval_request = {
            paymentTransactionId: response['itemTransactions'][0]['paymentTransactionId']
          }
          approval_response = Iyzipay::Model::Approval.new.create(approval_request, iyzipay_options)
          approval_response = JSON.parse approval_response
          
          if approval_response["status"] == "success"
            Response.new(true, message_from_transaction_result(response), response, response_options(response))
          else
            Response.new(false, message_from_transaction_result(approval_response), approval_response, response_options(approval_response))
          end
        else
          Response.new(false, message_from_transaction_result(response), response, response_options(response))
        end
      end

      def authorize(money, creditcard, options={})
        if submerchant_key(options).nil?
          return Response.new(false, "İşletmeye ait Iyzipay Alt Üye İşyeri kaydı bulunamadı", {}, {})
        end

        money = BigDecimal.new(money) / 100
        result = Iyzipay::Model::ThreedsInitialize.new.create(auth_request_data(money, creditcard, options), iyzipay_options)

        result = JSON.parse(result)
        if result['status'] == 'success'
          Response.new(true, message_from_transaction_result(result), result, response_options(result))
        else
          Response.new(false, message_from_transaction_result(result), result, response_options(result))
        end
      end

      def void(authorization, options={})
        request= {}
        create_cancel_request(request, authorization, options)
        create_void_pki_string(request)
        commit(:post, '/payment/cancel', request, options, @void_pki_string)
      end

      def verify(credit_card, options={})
        MultiResponse.run(:use_first_response) do |r|
          r.process { authorize(0.1, credit_card, options) }
          r.process(:ignore_result) { void(r.authorization, options) }
        end
      end

      def auth_request_data(money, creditcard, options)
        if options[:order_id] == nil
          uid = rand(36**8).to_s(36)
        else
          uid = options[:order_id]
        end

        {
          locale: Iyzipay::Model::Locale::TR,
          conversationId: "shopify_#{uid}",
          price: money.to_s,
          paidPrice: money.to_s,
          installment: 1,
          paymentChannel: Iyzipay::Model::PaymentChannel::WEB,
          basketId: uid,
          paymentGroup: Iyzipay::Model::PaymentGroup::PRODUCT,
          callbackUrl: full_checkout_path,
          currency: Iyzipay::Model::Currency::TRY,
          paymentCard: payment_card(creditcard),
          buyer: buyer(options),
          billingAddress: address(options[:billing_address] || options[:address]),
          shippingAddress: address(options[:shipping_address] || options[:address]),
          basketItems: [item(money, options)]
        }
      end

      def submerchant_price(money)
        static_commission = BigDecimal.new("0.25") # 0.25 TL sabit iyzico komisyonu
        percentage_commission = money * BigDecimal("0.0729") # %5 bizim komisyonumuz + %2.29 iyzico komisyonu
        total_commission = static_commission + percentage_commission
        money - total_commission
      end

      def submerchant_key(options)
        order = fetch_order(options)
        iyzipay_account = IyzipayAccount.where(enterprise_id: order.distributor_id).first

        if iyzipay_account
          iyzipay_account.submerchant_key
        end
        
        # enterprise = Enterprise.find(order.distributor_id)
        # property = Spree::Property.where(name: "IYZIPAY_SUBMERCHANT_KEY").first
        # enterprise.producer_properties.where(property_id: property).first.value
      end

      def payment_card(creditcard)
        {
          cardHolderName: creditcard.name,
          cardNumber: creditcard.number,
          expireYear: creditcard.year.to_s,
          expireMonth: creditcard.month.to_s.rjust(2, "0"),
          cvc: creditcard.verification_value,
          registerCard: 0
        }
      end

      def buyer(options)
        billing_data = options[:billing_address] || options[:address] || {}
        if billing_data[:phone] && !billing_data[:phone].start_with?("+9")
          billing_data[:phone] = "+9" + billing_data[:phone]
        end

        {
          id: options[:customer],
          name: options[:name] || "not provided",
          surname: options[:surname] || "not provided",
          identityNumber: "SHOPIFY_#{options[:name]}",
          email: options[:email],
          gsmNumber: billing_data[:phone] || "not provided",
          registrationDate: '2013-04-21 15:12:09',
          lastLoginDate: '2015-10-05 12:43:35',
          registrationAddress: billing_data[:address1] || "not provided",
          city: billing_data[:city] || "not provided",
          country: billing_data[:country] || "not provided",
          zipCode: '000',
          ip: options[:ip]
        }
      end

      def address(address_data)
        address_data ||= {}

        {
          address: address_data[:address1] || "not provided",
          zipCode: address_data[:zip] || "not provided",
          contactName: address_data[:name] || "not provided",
          city: address_data[:city] || "not provided",
          country: address_data[:country] || "not provided",
        }
      end

      def item(money, options)
        {
          id: '12349865322',
          name: 'FOOD',
          category1: 'FOOD',
          itemType: Iyzipay::Model::BasketItemType::PHYSICAL,
          price: money.to_s,
          subMerchantPrice: submerchant_price(money).to_s,
          subMerchantKey: submerchant_key(options),
        }
      end

      def supports_scrubbing?
        true
      end

      def scrub(transcript)
        transcript
      end

      private

      def message_from_transaction_result(result)
        if result['status'] == "success"
          "Transaction success"
        elsif result['status'] == "failure"
          if result['errorCode'].present?
            "#{result['errorMessage']} (#{result['errorCode']})"
          else
            md_status_description(result['mdStatus'])
          end
        else
          "Transaction rejected by gateway"
        end
      end

      def md_status_description(md_status)
        {
          "0" => "3-D Secure imzası geçersiz veya doğrulama",
          "2" => "Kart sahibi veya bankası sisteme kayıtlı değil",
          "3" => "Kartın bankası sisteme kayıtlı değil",
          "4" => "Doğrulama denemesi, kart sahibi sisteme daha sonra kayıt olmayı seçmiş",
          "5" => "Doğrulama yapılamıyor",
          "6" => "3-D Secure hatası",
          "7" => "Sistem hatası",
          "8" => "Bilinmeyen kart no",
          }[md_status] || "Bilinmeyen hata (#{md_status})"
      end

      def response_options(result)
        options = {
            :test => false,
            :authorization => result["conversationId"],
        }
        options
      end

      def full_checkout_path
        URI.join(url_helpers.root_url, url_helpers.checkout_path).to_s
        # "http://localhost/iyzipay/"
      end

      def url_helpers
        # This is how we can get the helpers with a usable root_url outside the controllers
        ::Rails.application.routes.default_url_options = ActionMailer::Base.default_url_options
        ::Rails.application.routes.url_helpers
      end

      def fetch_order(gateway_options)
        order_number = gateway_options[:order_id].split('-').first
        Spree::Order.find_by_number(order_number)
      end

      def fetch_payment(gateway_options)
        last_payment = OrderPaymentFinder.new(fetch_order(gateway_options)).last_payment
      end

    end
  end
end