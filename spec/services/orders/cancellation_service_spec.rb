require "rails_helper"

RSpec.describe Orders::CancellationService do
  let(:account) { create(:account, balance: 800.0) }
  let(:product) { create(:product, stock: 8) }
  let(:order) { create(:order, account: account, product: product, quantity: 2, total_amount: 200.0, status: Order::PENDING) }

  describe "cancelling a pending order" do
    it "cancels, refunds balance, restores stock" do
      described_class.call(order)

      order.reload
      expect(order.status).to eq(Order::CANCELLED)
      expect(order.cancelled_at).to be_present
      expect(account.reload.balance).to eq(1000.0)
      expect(product.reload.stock).to eq(10)
    end
  end

  describe "cancelling non-pending order" do
    it "raises NotCancellableError for processing order" do
      order.update!(status: Order::PROCESSING)
      expect { described_class.call(order) }
        .to raise_error(Orders::CancellationService::NotCancellableError)
    end

    it "raises NotCancellableError for completed order" do
      order.update!(status: Order::COMPLETED)
      expect { described_class.call(order) }
        .to raise_error(Orders::CancellationService::NotCancellableError)
    end
  end
end
