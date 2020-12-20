module Admin
  class IyzipaySubmerchantsController < Spree::Admin::BaseController
    def create
      enterprise_id = params["enterprise_id"]
      enterprise = Enterprise.find enterprise_id

      sub_merchant_type = params["sub_merchant_type"]
      

      ia = IyzipayAccount.new enterprise_id: enterprise_id, name: enterprise.name, gsm_number: enterprise.phone,
                              sub_merchant_type: sub_merchant_type, email: enterprise.email_address,
                              address: enterprise.address.address1 + " " + enterprise.address.address2.to_s,
                              sub_merchant_external_id: "OFN_#{enterprise.id}", identity_number: enterprise.abn
      ia.iban = params["iban"].gsub(' ', '')
      if sub_merchant_type == 'PERSONAL'
        contact_name, contact_surname = enterprise.contact_name.split
        contact_surname = contact_surname.join(' ') if contact_surname.is_a? Array
        ia.contact_name = contact_name
        ia.contact_surname = contact_surname
      else
        ia.tax_office = params["tax_office"].strip
        ia.legal_company_title = params["legal_company_title"]
      end
      
      if sub_merchant_type == 'LIMITED_OR_JOINT_STOCK_COMPANY'
        ia.tax_number = params["tax_number"].strip
      end

      if ia.valid?
        if ia.submit_to_iyzipay
          redirect_to main_app.edit_admin_enterprise_path(enterprise), notice: 'Alt üye işyeri başarıyla kaydedildi'
        else
          redirect_to main_app.edit_admin_enterprise_path(enterprise), flash: { error: ia.errors.full_messages.join('. ') }
        end
      else
        logger.error ia.errors.full_messages.join('. ')
        redirect_to main_app.edit_admin_enterprise_path(enterprise), flash: { error: ia.errors.full_messages.join('. ') }
      end

      
    end

    def model_class
      IyzipayAccount
    end
  end
end
