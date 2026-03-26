require "rails_helper"

RSpec.describe Account, type: :model do
  describe "associations" do
    it { should have_many(:orders) }
    it { should have_many(:transaction_records) }
  end

  describe "validations" do
    subject { create(:account) }

    it { should validate_presence_of(:name) }
    it { should validate_presence_of(:email) }
    it { should validate_uniqueness_of(:email) }
    it { should validate_numericality_of(:balance).is_greater_than_or_equal_to(0) }
  end

  describe "api_key generation" do
    it "generates api_key on create from email + secret" do
      account = create(:account, email: "test@example.com")
      secret = ENV.fetch("API_KEY_SECRET", "default_dev_secret")
      expected_key = OpenSSL::HMAC.hexdigest("SHA256", secret, "test@example.com")

      expect(account.api_key).to eq(expected_key)
    end

    it "generates unique keys for different emails" do
      a1 = create(:account, email: "one@example.com")
      a2 = create(:account, email: "two@example.com")

      expect(a1.api_key).not_to eq(a2.api_key)
    end

    it "does not overwrite existing api_key" do
      account = build(:account, api_key: "custom_key")
      account.save!

      expect(account.api_key).to eq("custom_key")
    end
  end
end
