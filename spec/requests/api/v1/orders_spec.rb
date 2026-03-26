require "rails_helper"

RSpec.describe "Api::V1::Orders", type: :request do
  let(:account) { create(:account, balance: 1000.0) }
  let(:product) { create(:product, stock: 10) }

  describe "POST /api/v1/orders" do
    let(:valid_params) do
      { product_id: product.id, quantity: 2, denomination: 100.0, reference_code: "REF-TEST-001" }
    end

    it "creates order and returns 202" do
      post "/api/v1/orders", params: valid_params, headers: auth_headers(account), as: :json

      expect(response).to have_http_status(:accepted)
      json = response.parsed_body
      expect(json["data"]["reference_code"]).to eq("REF-TEST-001")
      expect(json["data"]["status"]).to eq("pending")
      expect(json["data"]["total_amount"]).to eq("200.0")
    end

    it "returns existing order for duplicate reference_code (idempotent)" do
      post "/api/v1/orders", params: valid_params, headers: auth_headers(account), as: :json
      expect(response).to have_http_status(:accepted)

      post "/api/v1/orders", params: valid_params, headers: auth_headers(account), as: :json
      expect(response).to have_http_status(:ok)

      expect(Order.where(reference_code: "REF-TEST-001").count).to eq(1)
    end

    it "returns INSUFFICIENT_BALANCE" do
      account.update!(balance: 10.0)
      post "/api/v1/orders", params: valid_params, headers: auth_headers(account), as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      json = response.parsed_body
      expect(json["error"]["code"]).to eq("INSUFFICIENT_BALANCE")
    end

    it "returns OUT_OF_STOCK" do
      product.update!(stock: 0)
      post "/api/v1/orders", params: valid_params, headers: auth_headers(account), as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      json = response.parsed_body
      expect(json["error"]["code"]).to eq("OUT_OF_STOCK")
    end

    it "returns 401 without auth" do
      post "/api/v1/orders", params: valid_params, as: :json
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/orders/:id" do
    let!(:order) { create(:order, account: account) }

    it "returns order details" do
      get "/api/v1/orders/#{order.id}", headers: auth_headers(account), as: :json

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json["data"]["id"]).to eq(order.id)
      expect(json["data"]["reference_code"]).to eq(order.reference_code)
    end

    it "returns 404 for other account order" do
      other_account = create(:account)
      get "/api/v1/orders/#{order.id}", headers: auth_headers(other_account), as: :json

      expect(response).to have_http_status(:not_found)
    end

    it "returns 404 for non-existent order" do
      get "/api/v1/orders/99999", headers: auth_headers(account), as: :json
      expect(response).to have_http_status(:not_found)
    end
  end
end
