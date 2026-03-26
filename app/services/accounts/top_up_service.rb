module Accounts
  class TopUpService
    def self.call(account, amount)
      new(account, amount).call
    end

    def initialize(account, amount)
      @account = account
      @amount = amount.to_d
    end

    def call
      raise ArgumentError, "Amount must be greater than zero" unless @amount > 0

      ActiveRecord::Base.transaction do
        @account.lock!
        balance_before = @account.balance

        @account.update!(balance: @account.balance + @amount)

        transaction_record = TransactionRecord.create!(
          account: @account,
          transaction_type: TransactionRecord::CREDIT,
          amount: @amount,
          balance_before: balance_before,
          balance_after: @account.balance
        )

        { account: @account, transaction: transaction_record }
      end
    end
  end
end
