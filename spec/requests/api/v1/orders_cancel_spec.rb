require "rails_helper"

RSpec.describe "Api::V1::Orders#cancel", type: :request do
  let(:account) { create(:account, balance: 800.0) }
  let(:product) { create(:product, stock: 8) }

  describe "POST /api/v1/orders/:id/cancel" do
    it "cancels pending order and refunds balance + stock" do
      order = create(:order, account: account, product: product, quantity: 2, total_amount: 200.0, status: Order::PENDING)

      post "/api/v1/orders/#{order.id}/cancel", headers: auth_headers(account), as: :json

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json["data"]["status"]).to eq("cancelled")
      expect(account.reload.balance).to eq(1000.0)
      expect(product.reload.stock).to eq(10)
    end

    it "rejects cancellation of processing order" do
      order = create(:order, account: account, product: product, status: Order::PROCESSING)

      post "/api/v1/orders/#{order.id}/cancel", headers: auth_headers(account), as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      json = response.parsed_body
      expect(json["error"]["code"]).to eq("ORDER_NOT_CANCELLABLE")
    end

    it "rejects cancellation of completed order" do
      order = create(:order, account: account, product: product, status: Order::COMPLETED)

      post "/api/v1/orders/#{order.id}/cancel", headers: auth_headers(account), as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "returns 401 without auth" do
      order = create(:order, account: account, product: product)

      post "/api/v1/orders/#{order.id}/cancel", as: :json
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
