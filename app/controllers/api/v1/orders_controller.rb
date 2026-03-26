module Api
  module V1
    class OrdersController < ApplicationController
      before_action :authenticate!

      def create
        render_success({ message: "placeholder" }, :accepted)
      end

      def show
        # Will be replaced with real logic in Phase 6
        raise ActiveRecord::RecordNotFound.new("Order not found")
      end

      def cancel
        raise ActiveRecord::RecordNotFound.new("Order not found")
      end
    end
  end
end
