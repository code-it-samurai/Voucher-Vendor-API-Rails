class Product < ApplicationRecord
  has_many :orders, dependent: :restrict_with_error

  validates :name, presence: true
  validates :denomination, presence: true, numericality: { greater_than: 0 }
  validates :stock, numericality: { greater_than_or_equal_to: 0 }
  validates :currency, presence: true

  scope :active, -> { where(active: true) }
end
