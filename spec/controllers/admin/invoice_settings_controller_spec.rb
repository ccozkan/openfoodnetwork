# frozen_string_literal: true

require 'spec_helper'

describe Admin::InvoiceSettingsController, type: :controller do
  describe "#update" do
    let(:params) do
      {
        preferences: {
          enable_invoices?: 0,
          invoice_style2?: 1,
          enable_receipt_printing?: 1,
        }
      }
    end

    before do
      allow(controller).to(receive(:spree_current_user) { create(:admin_user) })
    end

    it "disables invoices" do
      expect do
        post(:update, params: params)
      end.to(change {
        Spree::Config[:enable_invoices?]
      }.to(false))
    end

    it "changes the invoice style" do
      expect do
        post(:update, params: params)
      end.to(change {
        Spree::Config[:invoice_style2?]
      }.to(true))
    end

    it "disables receipt printing" do
      expect do
        post(:update, params: params)
      end.to(change {
        Spree::Config[:enable_receipt_printing?]
      }.to(true))
    end
  end
end
