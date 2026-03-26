FactoryBot.define do
  factory :order do
    association :account
    association :product
    sequence(:reference_code) { |n| "REF-#{n}" }
    quantity { 1 }
    denomination { 100.0 }
    total_amount { 100.0 }
    status { Order::PENDING }
  end
end
