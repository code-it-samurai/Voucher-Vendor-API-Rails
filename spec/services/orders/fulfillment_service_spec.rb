require "rails_helper"

RSpec.describe Orders::FulfillmentService do
  let(:account) { create(:account, balance: 800.0) }
  let(:product) { create(:product, :test_success, stock: 8) }
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

  describe "test_behavior: failure" do
    let(:product) { create(:product, :test_failure, stock: 8) }

    it "raises FulfillmentError" do
      expect { described_class.call(order) }
        .to raise_error(Orders::FulfillmentService::FulfillmentError)
      expect(order.reload.status).to eq(Order::PROCESSING)
    end
  end

  describe "test_behavior: pending (transient failure then success)" do
    let(:product) { create(:product, :test_pending, stock: 8) }
    let(:threshold) { Orders::FulfillmentService::TRANSIENT_FAILURE_COUNT }

    it "raises FulfillmentError for each of the first #{Orders::FulfillmentService::TRANSIENT_FAILURE_COUNT} attempts" do
      threshold.times do |i|
        expect { described_class.call(order) }
          .to raise_error(Orders::FulfillmentService::FulfillmentError, /Simulated transient failure/)
        expect(order.reload.attempts).to eq(i + 1)
        expect(order.reload.status).to eq(Order::PROCESSING)
      end
    end

    it "completes the order on attempt #{Orders::FulfillmentService::TRANSIENT_FAILURE_COUNT + 1}" do
      order.update!(status: Order::PROCESSING, attempts: threshold)

      described_class.call(order)

      order.reload
      expect(order.status).to eq(Order::COMPLETED)
      expect(order.vouchers.count).to eq(order.quantity)
    end

    it "completes successfully after cycling through all failures" do
      threshold.times do
        expect { described_class.call(order) }
          .to raise_error(Orders::FulfillmentService::FulfillmentError)
      end

      expect { described_class.call(order) }.not_to raise_error

      order.reload
      expect(order.status).to eq(Order::COMPLETED)
      expect(order.attempts).to eq(threshold + 1)
      expect(order.vouchers.count).to eq(order.quantity)
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
