module Orders
  class RefundService
    def self.call(order)
      new(order).call
    end

    def initialize(order)
      @order = order
    end

    def call
      ActiveRecord::Base.transaction do
        account = @order.account.lock!
        product = @order.product.lock!

        balance_before = account.balance
        account.update!(balance: account.balance + @order.total_amount)
        product.update!(stock: product.stock + @order.quantity)

        TransactionRecord.create!(
          account: account,
          order: @order,
          transaction_type: TransactionRecord::REFUND,
          amount: @order.total_amount,
          balance_before: balance_before,
          balance_after: account.balance
        )
      end

      Rails.logger.info "[RefundService] Refunded: order=#{@order.id} amount=#{@order.total_amount} account=#{@order.account_id}"
    end
  end
end
