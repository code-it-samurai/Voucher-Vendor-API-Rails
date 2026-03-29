require "rails_helper"

RSpec.describe OrderFulfillmentJob, "retry exhaustion", type: :job do
  let(:account) { create(:account, balance: 200.0) }
  let(:product) { create(:product, stock: 10) }
  let(:order) do
    create(:order,
      account: account,
      product: product,
      quantity: 1,
      denomination: 100.0,
      total_amount: 100.0,
      status: Order::PROCESSING
    )
  end

  let(:msg) do
    {
      "class" => "OrderFulfillmentJob",
      "args" => [order.id],
      "error_message" => "Simulated failure after processing for test product"
    }
  end

  describe "sidekiq_retries_exhausted" do
    it "marks order as refunded and restores balance" do
      balance_before = account.balance

      described_class.sidekiq_retries_exhausted_block.call(msg, StandardError.new("boom"))

      order.reload
      account.reload

      expect(order.status).to eq(Order::REFUNDED)
      expect(order.failure_reason).to eq("Simulated failure after processing for test product")
      expect(account.balance).to eq(balance_before + order.total_amount)
    end

    it "restores product stock" do
      stock_before = product.stock

      described_class.sidekiq_retries_exhausted_block.call(msg, StandardError.new("boom"))

      expect(product.reload.stock).to eq(stock_before + order.quantity)
    end

    it "creates a refund transaction record" do
      expect {
        described_class.sidekiq_retries_exhausted_block.call(msg, StandardError.new("boom"))
      }.to change(TransactionRecord, :count).by(1)

      txn = TransactionRecord.last
      expect(txn.transaction_type).to eq(TransactionRecord::REFUND)
      expect(txn.amount).to eq(order.total_amount)
      expect(txn.order).to eq(order)
    end

    it "skips already completed orders" do
      order.update!(status: Order::COMPLETED)

      expect {
        described_class.sidekiq_retries_exhausted_block.call(msg, StandardError.new("boom"))
      }.not_to change { account.reload.balance }
    end

    it "skips already cancelled orders" do
      order.update!(status: Order::CANCELLED)

      expect {
        described_class.sidekiq_retries_exhausted_block.call(msg, StandardError.new("boom"))
      }.not_to change { account.reload.balance }
    end
  end
end
