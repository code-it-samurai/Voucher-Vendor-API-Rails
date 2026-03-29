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
      existing = Order.find_by(account_id: @account.id, reference_code: @reference_code)
      if existing
        Rails.logger.info "[PlacementService] Idempotent hit: order=#{existing.id} ref=#{@reference_code} account=#{@account.id}"
        return { order: existing, created: false }
      end

      total_amount = @denomination * @quantity

      order = nil
      ActiveRecord::Base.transaction do
        account = Account.lock.find(@account.id)
        raise InsufficientBalanceError, "Account balance is insufficient for this order" if account.balance < total_amount

        product = Product.lock.find_by(id: @product_id, active: true)
        raise ProductNotFoundError, "Product not found or inactive" unless product
        raise OutOfStockError, "Insufficient stock for requested quantity" if product.stock < @quantity

        balance_before = account.balance
        account.update!(balance: account.balance - total_amount)
        product.update!(stock: product.stock - @quantity)

        order = Order.create!(
          account: account,
          product: product,
          reference_code: @reference_code,
          quantity: @quantity,
          denomination: @denomination,
          total_amount: total_amount,
          status: Order::PENDING
        )

        TransactionRecord.create!(
          account: account,
          order: order,
          transaction_type: TransactionRecord::DEBIT,
          amount: total_amount,
          balance_before: balance_before,
          balance_after: account.balance,
          notes: "Debiting balance for order placement"
        )
      end

      OrderFulfillmentJob.perform_later(order.id)

      Rails.logger.info "[PlacementService] Order placed: order=#{order.id} ref=#{@reference_code} account=#{@account.id} product=#{@product_id} total=#{total_amount}"

      @account.reload
      { order: order, created: true }
    rescue ActiveRecord::RecordNotUnique
      existing = Order.find_by!(account_id: @account.id, reference_code: @reference_code)
      Rails.logger.info "[PlacementService] Race condition resolved: order=#{existing.id} ref=#{@reference_code} account=#{@account.id}"
      @account.reload
      { order: existing, created: false }
    end
  end
end
