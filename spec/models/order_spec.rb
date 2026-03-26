require "rails_helper"

RSpec.describe Order, type: :model do
  describe "associations" do
    it { should belong_to(:account) }
    it { should belong_to(:product) }
    it { should have_many(:vouchers).dependent(:destroy) }
  end

  describe "validations" do
    subject { build(:order) }

    it { should validate_presence_of(:reference_code) }
    it { should validate_uniqueness_of(:reference_code) }
    it { should validate_presence_of(:quantity) }
    it { should validate_numericality_of(:quantity).is_greater_than(0) }
    it { should validate_presence_of(:denomination) }
    it { should validate_numericality_of(:denomination).is_greater_than(0) }
    it { should validate_presence_of(:total_amount) }
    it { should validate_numericality_of(:total_amount).is_greater_than(0) }
    it { should validate_presence_of(:status) }
    it { should validate_inclusion_of(:status).in_array(Order::STATUSES) }
  end

  describe "status helpers" do
    it "responds to status query methods" do
      order = build(:order, status: Order::PENDING)
      expect(order.pending?).to be true
      expect(order.processing?).to be false
    end
  end

  describe "scopes" do
    it "pending scope returns only pending orders" do
      pending_order = create(:order, status: Order::PENDING)
      create(:order, status: Order::COMPLETED)

      expect(Order.pending).to eq([pending_order])
    end
  end
end
