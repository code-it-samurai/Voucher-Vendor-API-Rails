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
      if @order.product.test_behavior.present?
        Orders::TestProductSimulator.call(@order)
        @order.reload
        complete_order unless terminal_state?
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

    def generate_voucher_code
      "GC-#{SecureRandom.alphanumeric(12).upcase}"
    end
  end
end
