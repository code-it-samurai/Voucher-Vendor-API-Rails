module Orders
  class PlacementService
    class InsufficientBalanceError < StandardError; end
    class OutOfStockError < StandardError; end
    class ProductNotFoundError < StandardError; end

    def self.call(account, params)
      new(account, params).call
    end

    def initialize(account, params)
      @account = account
      @reference_code = params[:reference_code]
      @product_id = params[:product_id]
      @quantity = params[:quantity].to_i
      @denomination = params[:denomination].to_d
    end

    def call
      # Idempotency: return existing order if reference_code already used
      existing = @account.orders.find_by(reference_code: @reference_code)
      return { order: existing, created: false } if existing

      total_amount = @denomination * @quantity

      order = nil
      ActiveRecord::Base.transaction do
        # Lock account row for balance check
        @account.lock!
        raise InsufficientBalanceError, "Account balance is insufficient for this order" if @account.balance < total_amount

        # Lock product row for stock check
        product = Product.lock.find_by(id: @product_id, active: true)
        raise ProductNotFoundError, "Product not found or inactive" unless product
        raise OutOfStockError, "Insufficient stock for requested quantity" if product.stock < @quantity

        # Debit balance
        balance_before = @account.balance
        @account.update!(balance: @account.balance - total_amount)

        # Decrement stock
        product.update!(stock: product.stock - @quantity)

        # Create order
        order = Order.create!(
          account: @account,
          product: product,
          reference_code: @reference_code,
          quantity: @quantity,
          denomination: @denomination,
          total_amount: total_amount,
          status: Order::PENDING
        )

        # Audit trail
        TransactionRecord.create!(
          account: @account,
          order: order,
          transaction_type: TransactionRecord::DEBIT,
          amount: total_amount,
          balance_before: balance_before,
          balance_after: @account.balance
        )
      end

      # Enqueue fulfillment job
      OrderFulfillmentJob.perform_later(order.id)

      { order: order, created: true }
    rescue ActiveRecord::RecordNotUnique
      # Race condition: another request created the order with same reference_code
      existing = @account.orders.find_by!(reference_code: @reference_code)
      { order: existing, created: false }
    end
  end
end
