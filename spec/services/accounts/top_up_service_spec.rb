require "rails_helper"

RSpec.describe Accounts::TopUpService do
  let(:account) { create(:account, balance: 100.0) }

  it "credits balance and creates transaction record" do
    result = described_class.call(account, 500.0)

    expect(account.reload.balance).to eq(600.0)
    expect(result[:transaction].transaction_type).to eq("credit")
    expect(result[:transaction].amount).to eq(500.0)
    expect(result[:transaction].balance_before).to eq(100.0)
    expect(result[:transaction].balance_after).to eq(600.0)
  end

  it "raises for zero amount" do
    expect { described_class.call(account, 0) }.to raise_error(ArgumentError)
  end

  it "raises for negative amount" do
    expect { described_class.call(account, -50) }.to raise_error(ArgumentError)
  end
end
