require "rails_helper"

RSpec.describe Orders::PlacementService do
  let(:account) { create(:account, balance: 1000.0) }
  let(:product) { create(:product, denomination: 100.0, stock: 10) }

  let(:params) do
    { product_id: product.id, quantity: 2, denomination: 100.0, reference_code: "REF-001" }
  end

  describe "happy path" do
    it "creates order, debits balance, decrements stock, enqueues job" do
      result = described_class.call(account, params)

      expect(result[:created]).to be true
      order = result[:order]
      expect(order.status).to eq(Order::PENDING)
      expect(order.total_amount).to eq(200.0)

      expect(account.reload.balance).to eq(800.0)
      expect(product.reload.stock).to eq(8)
      expect(TransactionRecord.last.transaction_type).to eq("debit")
    end
  end

  describe "idempotency" do
    it "returns existing order for same reference_code" do
      first = described_class.call(account, params)
      second = described_class.call(account, params)

      expect(second[:created]).to be false
      expect(second[:order].id).to eq(first[:order].id)

      # Balance should only be debited once
      expect(account.reload.balance).to eq(800.0)
    end
  end

  describe "insufficient balance" do
    let(:account) { create(:account, balance: 50.0) }

    it "raises InsufficientBalanceError" do
      expect { described_class.call(account, params) }
        .to raise_error(Orders::PlacementService::InsufficientBalanceError)
      expect(account.reload.balance).to eq(50.0)
    end
  end

  describe "out of stock" do
    let(:product) { create(:product, stock: 1) }

    it "raises OutOfStockError when quantity exceeds stock" do
      expect { described_class.call(account, params) }
        .to raise_error(Orders::PlacementService::OutOfStockError)
      expect(product.reload.stock).to eq(1)
    end
  end

  describe "inactive product" do
    let(:product) { create(:product, :inactive) }

    it "raises ProductNotFoundError" do
      expect { described_class.call(account, params) }
        .to raise_error(Orders::PlacementService::ProductNotFoundError)
    end
  end
end
