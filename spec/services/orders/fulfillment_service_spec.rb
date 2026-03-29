require "rails_helper"

RSpec.describe Orders::FulfillmentService do
  let(:account) { create(:account, balance: 800.0) }
  let(:product) { create(:product, stock: 8) }
  let(:order) { create(:order, account: account, product: product, quantity: 2, total_amount: 200.0) }

  describe "successful fulfillment" do
    it "completes order and generates vouchers" do
      described_class.call(order)

      order.reload
      expect(order.status).to eq(Order::COMPLETED)
      expect(order.processed_at).to be_present
      expect(order.vouchers.count).to eq(2)
      expect(order.vouchers.first.code).to start_with("GC-")
      expect(order.vouchers.first.pin).to be_present
    end
  end

  describe "delegates to TestProductSimulator for test products" do
    let(:product) { create(:product, :test_success, stock: 8) }

    it "calls the simulator when test_behavior is present" do
      expect(Orders::TestProductSimulator).to receive(:call).with(order)
      described_class.call(order)
    end
  end

  describe "skips terminal states" do
    it "does nothing for completed orders" do
      order.update!(status: Order::COMPLETED)
      described_class.call(order)
      expect(order.reload.status).to eq(Order::COMPLETED)
    end

    it "does nothing for cancelled orders" do
      order.update!(status: Order::CANCELLED)
      described_class.call(order)
      expect(order.reload.status).to eq(Order::CANCELLED)
    end
  end
end
