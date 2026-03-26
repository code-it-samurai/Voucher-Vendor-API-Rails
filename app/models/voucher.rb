class Voucher < ApplicationRecord
  belongs_to :order

  validates :code, presence: true, uniqueness: true
end
