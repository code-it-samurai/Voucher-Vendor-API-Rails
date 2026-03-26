FactoryBot.define do
  factory :transaction_record do
    association :account
    transaction_type { TransactionRecord::CREDIT }
    amount { 100.0 }
    balance_before { 0.0 }
    balance_after { 100.0 }
  end
end
