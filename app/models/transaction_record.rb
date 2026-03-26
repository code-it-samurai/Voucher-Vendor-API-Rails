class TransactionRecord < ApplicationRecord
  CREDIT = "credit"
  DEBIT = "debit"
  REFUND = "refund"

  TYPES = [CREDIT, DEBIT, REFUND].freeze

  belongs_to :account
  belongs_to :order, optional: true

  validates :transaction_type, presence: true, inclusion: { in: TYPES }
  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :balance_before, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :balance_after, presence: true, numericality: { greater_than_or_equal_to: 0 }
end
