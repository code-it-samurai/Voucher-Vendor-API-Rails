module Orders
  class CancellationService
    class NotCancellableError < StandardError; end

    def self.call(order)
      new(order).call
    end

    def initialize(order)
      @order = order
    end

    def call
      ActiveRecord::Base.transaction do
        @order.lock!
        raise NotCancellableError, "Order can only be cancelled when pending" unless @order.pending?

        @order.update!(status: Order::CANCELLED, cancelled_at: Time.current)

        Orders::RefundService.call(@order)
      end
    end
  end
end
