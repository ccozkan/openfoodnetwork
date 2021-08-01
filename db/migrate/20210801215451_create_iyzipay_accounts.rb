class CreateIyzipayAccounts < ActiveRecord::Migration[6.1]
  def change
    create_table :iyzipay_accounts, id: false, force: :cascade do |t|
      t.primary_key :id, default: "nextval('iyzipay_accounts_id_seq'::regclass)"
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
    end

    add_index "inventory_items", ["enterprise_id", "variant_id"], name: "index_inventory_items_on_enterprise_id_and_variant_id", unique: true, using: :btree
  end
end
