require "rails_helper"

RSpec.describe "Response Envelope", type: :request do
  describe "success response format" do
    it "returns consistent SUCCESS envelope" do
      post "/api/v1/accounts", params: { name: "Test", email: "test@example.com" }, as: :json
      json = response.parsed_body

      expect(response).to have_http_status(:created)
      expect(json["status"]).to eq("SUCCESS")
      expect(json).to have_key("data")
    end
  end

  describe "error response format" do
    it "returns UNAUTHORIZED without API key" do
      get "/api/v1/accounts/me", as: :json
      json = response.parsed_body

      expect(response).to have_http_status(:unauthorized)
      expect(json["status"]).to eq("ERROR")
      expect(json["error"]["code"]).to eq("UNAUTHORIZED")
      expect(json["error"]["message"]).to be_present
    end
  end
end
