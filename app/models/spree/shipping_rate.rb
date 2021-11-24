# frozen_string_literal: true

module Spree
  class ShippingRate < ApplicationRecord
    belongs_to :shipment, class_name: 'Spree::Shipment'
    belongs_to :shipping_method, class_name: 'Spree::ShippingMethod', inverse_of: :shipping_rates

    scope :frontend,
          lambda {
            includes(:shipping_method)
              .where(ShippingMethod.on_frontend_query)
              .references(:shipping_method)
              .order('cost ASC')
          }
    scope :backend,
          lambda {
            includes(:shipping_method)
              .where(ShippingMethod.on_backend_query)
              .references(:shipping_method)
              .order('cost ASC')
          }

    delegate :order, :currency, to: :shipment
    delegate :name, to: :shipping_method

    def display_price
      Spree::Money.new(cost, { currency: currency })
    end

    alias display_cost display_price
  end
end
