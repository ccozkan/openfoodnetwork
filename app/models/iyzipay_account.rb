class IyzipayAccount < ActiveRecord::Base
  belongs_to :enterprise

  validates :contact_name, presence: true, if: ->{sub_merchant_type == 'PERSONAL'}
  validates :contact_surname, presence: true, if: ->{sub_merchant_type == 'PERSONAL'}
  validates :email, presence: true
  validates :address, presence: true
  validates :iban, presence: true
  validates :sub_merchant_external_id, presence: true
  validates :identity_number, presence: true
  validates :sub_merchant_type, presence: true
  validates :tax_office, presence: true, if: ->{sub_merchant_type == 'PRIVATE_COMPANY' || sub_merchant_type == 'LIMITED_OR_JOINT_STOCK_COMPANY'}
  validates :legal_company_title, presence: true, if: ->{sub_merchant_type == 'PRIVATE_COMPANY' || sub_merchant_type == 'LIMITED_OR_JOINT_STOCK_COMPANY'}
  validates :tax_number, presence: true, if: ->{sub_merchant_type == 'LIMITED_OR_JOINT_STOCK_COMPANY'}

  default_scope {where(deleted_at: nil)}
  scope :including_deleted, ->{ unscope(where: :deleted_at) }

  def submit_to_iyzipay
    require "iyzipay"

    options = Iyzipay::Options.new
    options.api_key = ENV.fetch('IYZIPAY_API_KEY')
    options.secret_key = ENV.fetch('IYZIPAY_SECRET')
    options.base_url = "https://api.iyzipay.com"

    request = {
      locale: Iyzipay::Model::Locale::TR,
      conversationId: '123456789',
      subMerchantExternalId: sub_merchant_external_id,
      subMerchantType: sub_merchant_type,
      address: address,
      email: email,
      gsmNumber: gsm_number,
      name: name,
      iban: iban,
      identityNumber: identity_number,
      currency: Iyzipay::Model::Currency::TRY
    }

    if sub_merchant_type == 'PERSONAL'
      request[:contactName] = contact_name
      request[:contactSurname] = contact_surname
    else
      request[:legalCompanyTitle] = legal_company_title
      request[:taxOffice] = tax_office
    end

    if sub_merchant_type == 'LIMITED_OR_JOINT_STOCK_COMPANY'
      request[:taxNumber] = tax_number
    end

    Rails.logger.error request
    response = Iyzipay::Model::SubMerchant.new.create(request, options)
    Rails.logger.error response
    response = JSON.parse(response)

    if response['status'] == 'success'
      self.submerchant_key = response['subMerchantKey']
      save!
      true
    else
      errors.add :base, "Alt üye işyeri kaydederken hata: #{response['errorCode']}(#{response['errorGroup']}) #{response['errorMessage']}"
      false
    end
  end
end
