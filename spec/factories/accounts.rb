FactoryBot.define do
  factory :account do
    name { "Test User" }
    sequence(:email) { |n| "user#{n}@example.com" }

    trait :with_balance do
      balance { 1000.0 }
    end
  end
end
