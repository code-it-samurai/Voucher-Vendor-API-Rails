require "rails_helper"

RSpec.describe "Api::V1::Products", type: :request do
  let(:account) { create(:account) }

  describe "GET /api/v1/products" do
    it "lists active products" do
      create(:product, name: "Active Card", active: true)
      create(:product, name: "Inactive Card", active: false)

      get "/api/v1/products", headers: auth_headers(account), as: :json

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      names = json["data"].map { |p| p["name"] }
      expect(names).to include("Active Card")
      expect(names).not_to include("Inactive Card")
    end

    it "returns 401 without auth" do
      get "/api/v1/products", as: :json
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "POST /api/v1/products/:id/replenish" do
    let!(:product) { create(:product, stock: 10) }

    it "adds stock to product" do
      post "/api/v1/products/#{product.id}/replenish", params: { quantity: 50 }, headers: auth_headers(account), as: :json

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json["data"]["stock"]).to eq(60)
      expect(product.reload.stock).to eq(60)
    end

    it "rejects zero quantity" do
      post "/api/v1/products/#{product.id}/replenish", params: { quantity: 0 }, headers: auth_headers(account), as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "rejects negative quantity" do
      post "/api/v1/products/#{product.id}/replenish", params: { quantity: -5 }, headers: auth_headers(account), as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "returns 404 for non-existent product" do
      post "/api/v1/products/99999/replenish", params: { quantity: 10 }, headers: auth_headers(account), as: :json

      expect(response).to have_http_status(:not_found)
    end
  end
end
