class CreateIyzipayAccounts < ActiveRecord::Migration[6.1]
  def change
    create_table :iyzipay_accounts do |t|
      t.references :enterprise, foreign_key: true
      t.text :submerchant_key
      t.text :name
      t.text :gsm_number
      t.text :contact_name
      t.text :contact_surname
      t.text :email
      t.text :address
      t.text :iban
      t.text :sub_merchant_external_id
      t.text :identity_number
      t.text :sub_merchant_type
      t.text :tax_office
      t.text :legal_company_title
      t.text :tax_number

      t.timestamps
      t.datetime :deleted_at
    end
  end
end
