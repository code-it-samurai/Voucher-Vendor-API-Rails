module Orders
  class FulfillmentService
    class FulfillmentError < StandardError; end

    def self.call(order)
      new(order).call
    end

    def initialize(order)
      @order = order
    end

    def call
      return if terminal_state?

      ActiveRecord::Base.transaction do
        @order.lock!
        return if terminal_state?

        @order.update!(status: Order::PROCESSING, attempts: @order.attempts + 1)
      end

      process_order
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
        # Stays in processing forever — for polling tests
        loop { sleep 60 }
      when "refund"
        raise FulfillmentError, "Simulated failure after processing for test product"
      else
        # Normal product: simulate downstream processing
        simulate_downstream
      end
    end

    def simulate_downstream
      sleep(rand(2..5)) if Rails.env.production? || Rails.env.development?

      # ~20% random failure in non-test environments
      if !Rails.env.test? && rand(5).zero?
        raise FulfillmentError, "Downstream fulfillment failed"
      end

      complete_order
    end

    def complete_order
      ActiveRecord::Base.transaction do
        @order.lock!

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
    end

    def generate_voucher_code
      "GC-#{SecureRandom.alphanumeric(12).upcase}"
    end
  end
end
