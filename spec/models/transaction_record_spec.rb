require "rails_helper"

RSpec.describe TransactionRecord, type: :model do
  describe "associations" do
    it { should belong_to(:account) }
    it { should belong_to(:order).optional }
  end

  describe "validations" do
    it { should validate_presence_of(:transaction_type) }
    it { should validate_inclusion_of(:transaction_type).in_array(TransactionRecord::TYPES) }
    it { should validate_presence_of(:amount) }
    it { should validate_numericality_of(:amount).is_greater_than(0) }
    it { should validate_presence_of(:balance_before) }
    it { should validate_numericality_of(:balance_before).is_greater_than_or_equal_to(0) }
    it { should validate_presence_of(:balance_after) }
    it { should validate_numericality_of(:balance_after).is_greater_than_or_equal_to(0) }
  end
end
