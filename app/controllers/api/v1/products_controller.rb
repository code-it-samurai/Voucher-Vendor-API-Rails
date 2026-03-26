module Api
  module V1
    class ProductsController < ApplicationController
      before_action :authenticate!

      def index
        products = Product.active.order(:name)
        render_success(products.map { |p| product_json(p) })
      end

      def replenish
        quantity = params.require(:quantity).to_i

        if quantity <= 0
          return render_error("INVALID_AMOUNT", "Quantity must be greater than zero", :unprocessable_entity)
        end

        product = Product.find(params[:id])

        ActiveRecord::Base.transaction do
          product.lock!
          product.update!(stock: product.stock + quantity)
        end

        render_success(product_json(product))
      end

      private

      def product_json(product)
        {
          id: product.id,
          name: product.name,
          denomination: product.denomination.to_s,
          currency: product.currency,
          stock: product.stock,
          active: product.active
        }
      end
    end
  end
end
