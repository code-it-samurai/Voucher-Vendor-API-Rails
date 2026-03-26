FactoryBot.define do
  factory :voucher do
    association :order
    sequence(:code) { |n| "VOUCHER-#{n}" }
    pin { "1234" }
    claim_url { "https://example.com/claim" }
    expires_at { 1.year.from_now }
  end
end
