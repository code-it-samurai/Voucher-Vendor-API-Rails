require "rails_helper"

RSpec.describe "Voucher generation during fulfillment" do
  let(:account) { create(:account, balance: 1000.0) }
  let(:product) { create(:product, :test_success, stock: 20) }

  it "generates one voucher per quantity unit" do
    order = create(:order, account: account, product: product, quantity: 3, total_amount: 300.0)
    Orders::FulfillmentService.call(order)

    expect(order.reload.vouchers.count).to eq(3)
  end

  it "populates code, pin, claim_url, and expires_at on each voucher" do
    order = create(:order, account: account, product: product, quantity: 1, total_amount: 100.0)
    Orders::FulfillmentService.call(order)

    voucher = order.reload.vouchers.first
    expect(voucher.code).to match(/\AGC-[A-Z0-9]{12}\z/)
    expect(voucher.pin).to match(/\A\d{4}\z/)
    expect(voucher.claim_url).to start_with("https://vouchers.example.com/claim/")
    expect(voucher.expires_at).to be_within(1.day).of(1.year.from_now)
  end

  it "generates unique codes across vouchers" do
    order = create(:order, account: account, product: product, quantity: 5, total_amount: 500.0)
    Orders::FulfillmentService.call(order)

    codes = order.reload.vouchers.pluck(:code)
    expect(codes.uniq.size).to eq(5)
  end
end
