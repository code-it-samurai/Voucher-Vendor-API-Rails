require "rails_helper"

RSpec.describe Orders::TestProductSimulator do
  let(:account) { create(:account, balance: 800.0) }
  let(:product) { create(:product, :test_success, stock: 8) }
  let(:order) { create(:order, account: account, product: product, quantity: 2, total_amount: 200.0) }
  let(:threshold) { described_class::TRANSIENT_FAILURE_COUNT }

  describe "test_behavior: success" do
    it "returns without raising" do
      expect { described_class.call(order) }.not_to raise_error
    end
  end

  describe "test_behavior: failure" do
    let(:product) { create(:product, :test_failure, stock: 8) }

    it "raises FulfillmentError" do
      expect { described_class.call(order) }
        .to raise_error(Orders::FulfillmentService::FulfillmentError, /Simulated permanent failure/)
    end
  end

  describe "test_behavior: pending (transient failure then success)" do
    let(:product) { create(:product, :test_pending, stock: 8) }

    it "raises FulfillmentError for each of the first #{Orders::TestProductSimulator::TRANSIENT_FAILURE_COUNT} attempts" do
      threshold.times do |i|
        order.update!(attempts: i + 1)
        expect { described_class.call(order) }
          .to raise_error(Orders::FulfillmentService::FulfillmentError, /Simulated transient failure/)
      end
    end

    it "returns without raising on attempt #{Orders::TestProductSimulator::TRANSIENT_FAILURE_COUNT + 1}" do
      order.update!(attempts: threshold + 1)
      expect { described_class.call(order) }.not_to raise_error
    end
  end

  describe "test_behavior: refund (transient failure then definitive failure)" do
    let(:product) { create(:product, :test_refund, stock: 8) }

    it "raises FulfillmentError for each of the first #{Orders::TestProductSimulator::TRANSIENT_FAILURE_COUNT} attempts" do
      threshold.times do |i|
        order.update!(attempts: i + 1)
        expect { described_class.call(order) }
          .to raise_error(Orders::FulfillmentService::FulfillmentError, /Simulated transient failure/)
      end
    end

    it "refunds the order on the decisive attempt without raising" do
      order.update!(status: Order::PROCESSING, attempts: threshold + 1)

      expect { described_class.call(order) }.not_to raise_error

      order.reload
      expect(order.status).to eq(Order::REFUNDED)
      expect(order.failure_reason).to be_present
    end

    it "restores account balance on definitive failure" do
      order.update!(status: Order::PROCESSING, attempts: threshold + 1)
      balance_before = account.reload.balance

      described_class.call(order)

      expect(account.reload.balance).to eq(balance_before + order.total_amount)
    end

    it "restores product stock on definitive failure" do
      order.update!(status: Order::PROCESSING, attempts: threshold + 1)
      stock_before = product.reload.stock

      described_class.call(order)

      expect(product.reload.stock).to eq(stock_before + order.quantity)
    end

    it "skips refund if already refunded" do
      order.update!(status: Order::REFUNDED, attempts: threshold + 1)

      expect { described_class.call(order) }.not_to raise_error
      expect(account.reload.balance).to eq(800.0)
    end
  end

  describe "end-to-end via FulfillmentService" do
    describe "pending product completes after transient failures" do
      let(:product) { create(:product, :test_pending, stock: 8) }

      it "cycles through failures then completes" do
        threshold.times do
          expect { Orders::FulfillmentService.call(order) }
            .to raise_error(Orders::FulfillmentService::FulfillmentError)
        end

        expect { Orders::FulfillmentService.call(order) }.not_to raise_error

        order.reload
        expect(order.status).to eq(Order::COMPLETED)
        expect(order.attempts).to eq(threshold + 1)
        expect(order.vouchers.count).to eq(order.quantity)
      end
    end

    describe "refund product refunds after transient failures" do
      let(:product) { create(:product, :test_refund, stock: 8) }

      it "cycles through failures then refunds" do
        threshold.times do
          expect { Orders::FulfillmentService.call(order) }
            .to raise_error(Orders::FulfillmentService::FulfillmentError)
        end

        expect { Orders::FulfillmentService.call(order) }.not_to raise_error

        order.reload
        expect(order.status).to eq(Order::REFUNDED)
        expect(order.attempts).to eq(threshold + 1)
        expect(order.vouchers).to be_empty
      end
    end
  end
end
