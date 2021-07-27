class SalesAgreement < ActiveRecord::Base
  validates :order_id, presence: true
  validates :content, presence: true
end