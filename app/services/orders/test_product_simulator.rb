module Orders
  class TestProductSimulator
    # Number of attempts that will fail before "pending"/"refund" test products
    # reach their decisive attempt. The product raises FulfillmentError on
    # attempts 1..TRANSIENT_FAILURE_COUNT, then either succeeds or fails
    # definitively on attempt TRANSIENT_FAILURE_COUNT + 1.
    TRANSIENT_FAILURE_COUNT = 3

    def self.call(order)
      new(order).call
    end

    def initialize(order)
      @order = order
    end

    def call
      case @order.product.test_behavior
      when "success"  then nil # fall through to real complete_order
      when "failure"  then raise FulfillmentService::FulfillmentError, "Simulated permanent failure"
      when "pending"  then simulate_transient_then_succeed
      when "refund"   then simulate_transient_then_fail
      end
    end

    private

    def simulate_transient_then_succeed
      return if @order.attempts > TRANSIENT_FAILURE_COUNT
      raise FulfillmentService::FulfillmentError,
        "Simulated transient failure (attempt #{@order.attempts}, succeeds after #{TRANSIENT_FAILURE_COUNT})"
    end

    def simulate_transient_then_fail
      if @order.attempts <= TRANSIENT_FAILURE_COUNT
        raise FulfillmentService::FulfillmentError,
          "Simulated transient failure (attempt #{@order.attempts}, fails after #{TRANSIENT_FAILURE_COUNT})"
      else
        fail_and_refund_order
      end
    end

    def fail_and_refund_order
      ActiveRecord::Base.transaction do
        @order.lock!
        return if @order.refunded? || @order.failed?

        @order.update!(status: Order::FAILED, failure_reason: "Simulated definitive failure for test product")
        Orders::RefundService.call(@order)
        @order.update!(status: Order::REFUNDED)
      end

      Rails.logger.warn "[TestProductSimulator] Failed definitively: order=#{@order.id}"
    end
  end
end
