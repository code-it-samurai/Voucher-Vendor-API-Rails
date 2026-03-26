class OrderFulfillmentJob < ApplicationJob
  queue_as :default
  
  sidekiq_options retry: 5

  sidekiq_retries_exhausted do |msg, _exception|
    order_id = msg["args"].first
    order = Order.find(order_id)

    ActiveRecord::Base.transaction do
      order.lock!
      return if order.completed? || order.cancelled? || order.refunded?

      order.update!(
        status: Order::FAILED,
        failure_reason: msg["error_message"]
      )

      Orders::RefundService.call(order)
      order.update!(status: Order::REFUNDED)
    end
  rescue => e
    Rails.logger.error "Failed to process exhausted retries for order #{order_id}: #{e.message}"
  end

  def perform(order_id)
    order = Order.find(order_id)
    Orders::FulfillmentService.call(order)
  end
end
