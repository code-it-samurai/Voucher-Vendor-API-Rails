class OrderFulfillmentJob < ApplicationJob
  queue_as :default

  # retry budget must be >= TestProductSimulator::TRANSIENT_FAILURE_COUNT (3)
  # so "pending" test products can exhaust their failures and eventually succeed.
  sidekiq_options retry: 5

  sidekiq_retry_in { |_count, _exception| 30 }

  sidekiq_retries_exhausted do |msg, _exception|
    args = msg["args"].first
    order_id = args.is_a?(Hash) ? args["arguments"].first : args
    order = Order.find(order_id)

    ActiveRecord::Base.transaction do
      order.lock!
      next if order.completed? || order.cancelled? || order.refunded?

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
    Rails.logger.info "[FulfillmentJob] Succeeded: order=#{order_id} execution=#{executions}"
  rescue Orders::FulfillmentService::FulfillmentError => e
    Rails.logger.warn "[FulfillmentJob] Transient failure: order=#{order_id} execution=#{executions} error=#{e.message}"
    raise
  rescue => e
    Rails.logger.error "[FulfillmentJob] Unexpected error: order=#{order_id} execution=#{executions} error=#{e.class}: #{e.message}"
    raise
  end
end
