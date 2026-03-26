require "rails_helper"

RSpec.describe OrderFulfillmentJob, type: :job do
  let(:account) { create(:account, balance: 800.0) }
  let(:product) { create(:product, :test_success, stock: 8) }
  let(:order) { create(:order, account: account, product: product, quantity: 1, total_amount: 100.0) }

  it "calls FulfillmentService" do
    expect(Orders::FulfillmentService).to receive(:call).with(order)
    described_class.perform_now(order.id)
  end
end
