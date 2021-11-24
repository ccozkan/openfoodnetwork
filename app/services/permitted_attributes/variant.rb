# frozen_string_literal: true

module PermittedAttributes
  class Variant
    def self.attributes
      %i[
        id
sku
on_hand
on_demand
        price
unit_value
unit_description
        display_name
display_as
        weight
height
width
depth
      ]
    end
  end
end
