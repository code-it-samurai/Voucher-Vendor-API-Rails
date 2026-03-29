class OrderFulfillmentJob < ApplicationJob
  queue_as :default
  
  sidekiq_options retry: 5

  sidekiq_retry_in { |_count, _exception| 30 }

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

    Rails.logger.warn "[FulfillmentJob] Retries exhausted: order=#{order_id} reason=#{msg["error_message"]}"
  rescue => e
    Rails.logger.error "[FulfillmentJob] Failed to handle exhausted retries for order #{order_id}: #{e.message}"
  end

  def perform(order_id)
    Rails.logger.info "[FulfillmentJob] Starting: order=#{order_id} execution=#{executions}"
    order = Order.find(order_id)
    Orders::FulfillmentService.call(order)
  rescue => e
    Rails.logger.warn "[FulfillmentJob] Attempt failed: order=#{order_id} execution=#{executions} error=#{e.message}"
    raise
  end
end
