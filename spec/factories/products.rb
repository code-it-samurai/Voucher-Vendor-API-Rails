FactoryBot.define do
  factory :product do
    name { "Amazon Gift Card" }
    denomination { 100.0 }
    currency { "INR" }
    active { true }
    stock { 10 }

    trait :out_of_stock do
      stock { 0 }
    end

    trait :inactive do
      active { false }
    end

    trait :test_success do
      name { "Test - Always Succeeds" }
      test_behavior { "success" }
    end

    trait :test_failure do
      name { "Test - Always Fails" }
      test_behavior { "failure" }
    end

    trait :test_pending do
      name { "Test - Stays Pending" }
      test_behavior { "pending" }
    end
  end
end
