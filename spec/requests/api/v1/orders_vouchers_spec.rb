require "rails_helper"

RSpec.describe "Order vouchers in API response", type: :request do
  let(:account) { create(:account, balance: 1000.0) }
  let(:product) { create(:product, :test_success, stock: 20) }

  it "includes voucher details in completed order response" do
    order = create(:order, account: account, product: product, quantity: 2, total_amount: 200.0)
    Orders::FulfillmentService.call(order)

    get "/api/v1/orders/#{order.id}", headers: auth_headers(account), as: :json

    json = response.parsed_body
    expect(json["data"]["status"]).to eq("completed")
    expect(json["data"]["vouchers"].size).to eq(2)
    expect(json["data"]["vouchers"].first).to include("code", "pin", "claim_url", "expires_at")
  end

  it "does not include vouchers for pending orders" do
    order = create(:order, account: account, product: product, quantity: 1, total_amount: 100.0)

    get "/api/v1/orders/#{order.id}", headers: auth_headers(account), as: :json

    json = response.parsed_body
    expect(json["data"]["status"]).to eq("pending")
    expect(json["data"]).not_to have_key("vouchers")
  end
end
