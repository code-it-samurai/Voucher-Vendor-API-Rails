require "rails_helper"

RSpec.describe Orders::RefundService do
  let(:account) { create(:account, balance: 800.0) }
  let(:product) { create(:product, stock: 8) }
  let(:order) { create(:order, account: account, product: product, quantity: 2, total_amount: 200.0) }

  it "credits balance, restores stock, creates refund transaction" do
    described_class.call(order)

    expect(account.reload.balance).to eq(1000.0)
    expect(product.reload.stock).to eq(10)

    txn = TransactionRecord.last
    expect(txn.transaction_type).to eq("refund")
    expect(txn.amount).to eq(200.0)
    expect(txn.balance_before).to eq(800.0)
    expect(txn.balance_after).to eq(1000.0)
  end
end
