module Api
  module V1
    class OrdersController < ApplicationController
      before_action :authenticate!

      def create
        result = Orders::PlacementService.call(current_account, order_params)
        status = result[:created] ? :accepted : :ok

        render_success(order_json(result[:order]), status)
      rescue Orders::PlacementService::InsufficientBalanceError => e
        render_error("INSUFFICIENT_BALANCE", e.message, :unprocessable_entity)
      rescue Orders::PlacementService::OutOfStockError => e
        render_error("OUT_OF_STOCK", e.message, :unprocessable_entity)
      rescue Orders::PlacementService::ProductNotFoundError => e
        render_error("PRODUCT_NOT_FOUND", e.message, :not_found)
      end

      def show
        order = current_account.orders.find(params[:id])
        render_success(order_json(order))
      end

      def cancel
        order = current_account.orders.find(params[:id])
        Orders::CancellationService.call(order)
        render_success(order_json(order.reload))
      rescue Orders::CancellationService::NotCancellableError => e
        render_error("ORDER_NOT_CANCELLABLE", e.message, :unprocessable_entity)
      end

      private

      def order_params
        params.permit(:product_id, :quantity, :denomination, :reference_code)
      end

      def order_json(order)
        data = {
          id: order.id,
          reference_code: order.reference_code,
          product_id: order.product_id,
          quantity: order.quantity,
          denomination: order.denomination.to_s,
          total_amount: order.total_amount.to_s,
          status: order.status,
          created_at: order.created_at
        }

        if order.completed?
          data[:vouchers] = order.vouchers.map do |v|
            { code: v.code, pin: v.pin, claim_url: v.claim_url, expires_at: v.expires_at }
          end
        end

        data[:failure_reason] = order.failure_reason if order.failed? || order.refunded?
        data[:cancelled_at] = order.cancelled_at if order.cancelled?

        data
      end
    end
  end
end
