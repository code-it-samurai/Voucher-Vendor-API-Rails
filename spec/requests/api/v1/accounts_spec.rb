require "rails_helper"

RSpec.describe "Api::V1::Accounts", type: :request do
  describe "POST /api/v1/accounts" do
    it "creates an account and returns api_key" do
      post "/api/v1/accounts", params: { account: { name: "Prat", email: "prat@example.com" } }, as: :json

      expect(response).to have_http_status(:created)
      json = response.parsed_body
      expect(json["status"]).to eq("SUCCESS")
      expect(json["data"]["name"]).to eq("Prat")
      expect(json["data"]["email"]).to eq("prat@example.com")
      expect(json["data"]["balance"]).to eq("0.0")
      expect(json["data"]["api_key"]).to be_present
    end

    it "returns error for duplicate email" do
      create(:account, email: "prat@example.com")
      post "/api/v1/accounts", params: { account: { name: "Prat", email: "prat@example.com" } }, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      json = response.parsed_body
      expect(json["status"]).to eq("ERROR")
      expect(json["error"]["code"]).to eq("INVALID_INPUT")
    end

    it "returns error for missing fields" do
      post "/api/v1/accounts", params: { account: { name: "" } }, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      json = response.parsed_body
      expect(json["status"]).to eq("ERROR")
    end
  end

  describe "GET /api/v1/accounts/me" do
    let(:account) { create(:account, :with_balance) }

    it "returns current account without api_key" do
      get "/api/v1/accounts/me", headers: auth_headers(account), as: :json

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json["data"]["email"]).to eq(account.email)
      expect(json["data"]["balance"]).to eq("1000.0")
      expect(json["data"]).not_to have_key("api_key")
    end

    it "returns 401 without auth" do
      get "/api/v1/accounts/me", as: :json
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "POST /api/v1/accounts/top_up" do
    let(:admin) { create(:account, :admin) }

    it "credits balance and returns transaction" do
      post "/api/v1/accounts/top_up", params: { amount: 500.0 }, headers: auth_headers(admin), as: :json

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json["data"]["balance"]).to eq("500.0")
      expect(json["data"]["transaction"]["type"]).to eq("credit")
      expect(json["data"]["transaction"]["amount"]).to eq("500.0")
    end

    it "rejects negative amount" do
      post "/api/v1/accounts/top_up", params: { amount: -10 }, headers: auth_headers(admin), as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      json = response.parsed_body
      expect(json["error"]["code"]).to eq("INVALID_AMOUNT")
    end

    it "rejects zero amount" do
      post "/api/v1/accounts/top_up", params: { amount: 0 }, headers: auth_headers(admin), as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "returns 401 without auth" do
      post "/api/v1/accounts/top_up", params: { amount: 100 }, as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns 403 for non-admin" do
      regular = create(:account)
      post "/api/v1/accounts/top_up", params: { amount: 100 }, headers: auth_headers(regular), as: :json

      expect(response).to have_http_status(:forbidden)
      json = response.parsed_body
      expect(json["error"]["code"]).to eq("FORBIDDEN")
    end
  end
end
