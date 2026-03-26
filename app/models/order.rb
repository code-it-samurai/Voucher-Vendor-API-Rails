class Order < ApplicationRecord
  PENDING = "pending"
  PROCESSING = "processing"
  COMPLETED = "completed"
  FAILED = "failed"
  REFUNDED = "refunded"
  CANCELLED = "cancelled"

  STATUSES = [PENDING, PROCESSING, COMPLETED, FAILED, REFUNDED, CANCELLED].freeze

  belongs_to :account
  belongs_to :product
  has_many :vouchers, dependent: :destroy

  validates :reference_code, presence: true, uniqueness: true
  validates :quantity, presence: true, numericality: { greater_than: 0 }
  validates :denomination, presence: true, numericality: { greater_than: 0 }
  validates :total_amount, presence: true, numericality: { greater_than: 0 }
  validates :status, presence: true, inclusion: { in: STATUSES }

  scope :pending, -> { where(status: PENDING) }

  def pending?    = status == PENDING
  def processing? = status == PROCESSING
  def completed?  = status == COMPLETED
  def failed?     = status == FAILED
  def refunded?   = status == REFUNDED
  def cancelled?  = status == CANCELLED
end
