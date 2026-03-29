module Orders
  class FulfillmentService
    class FulfillmentError < StandardError; end

    # Number of attempts that will fail before a "pending" test product succeeds.
    # The product raises FulfillmentError on attempts 1..TRANSIENT_FAILURE_COUNT,
    # then succeeds on attempt TRANSIENT_FAILURE_COUNT + 1.
    TRANSIENT_FAILURE_COUNT = 3

    def self.call(order)
      new(order).call
    end

    def initialize(order)
      @order = order
    end

    def call
      return if terminal_state?

      should_process = false
      ActiveRecord::Base.transaction do
        @order.lock!
        unless terminal_state?
          @order.update!(status: Order::PROCESSING, attempts: @order.attempts + 1)
          should_process = true
        end
      end

      if should_process
        Rails.logger.info "[FulfillmentService] Processing: order=#{@order.id} attempt=#{@order.attempts}"
        process_order
      end
    end

    private

    def terminal_state?
      !@order.pending? && !@order.processing?
    end

    def process_order
      behavior = @order.product.test_behavior

      case behavior
      when "success"
        complete_order
      when "failure"
        raise FulfillmentError, "Simulated failure for test product"
      when "pending"
        if @order.attempts <= TRANSIENT_FAILURE_COUNT
          raise FulfillmentError, "Simulated transient failure (attempt #{@order.attempts}, succeeds after #{TRANSIENT_FAILURE_COUNT})"
        else
          complete_order
        end
      when "refund"
        if @order.attempts <= TRANSIENT_FAILURE_COUNT
          raise FulfillmentError, "Simulated transient failure (attempt #{@order.attempts}, fails after #{TRANSIENT_FAILURE_COUNT})"
        else
          fail_order("Simulated definitive failure for test product")
        end
      else
        simulate_downstream
      end
    end

    def simulate_downstream
      sleep(rand(2..5)) if Rails.env.production? || Rails.env.development?

      if !Rails.env.test? && rand(5).zero?
        raise FulfillmentError, "Downstream fulfillment failed"
      end

      complete_order
    end

    def complete_order
      ActiveRecord::Base.transaction do
        @order.lock!
        return if @order.completed?

        @order.quantity.times do
          Voucher.create!(
            order: @order,
            code: generate_voucher_code,
            pin: rand(1000..9999).to_s,
            claim_url: "https://vouchers.example.com/claim/#{SecureRandom.urlsafe_base64(16)}",
            expires_at: 1.year.from_now
          )
        end

        @order.update!(status: Order::COMPLETED, processed_at: Time.current)
      end

      Rails.logger.info "[FulfillmentService] Completed: order=#{@order.id} vouchers=#{@order.quantity}"
    end

    def fail_order(reason)
      ActiveRecord::Base.transaction do
        @order.lock!
        return if @order.refunded? || @order.failed?

        @order.update!(status: Order::FAILED, failure_reason: reason)
        Orders::RefundService.call(@order)
        @order.update!(status: Order::REFUNDED)
      end

      Rails.logger.warn "[FulfillmentService] Failed definitively: order=#{@order.id} reason=#{reason}"
    end

    def generate_voucher_code
      "GC-#{SecureRandom.alphanumeric(12).upcase}"
    end
  end
end
