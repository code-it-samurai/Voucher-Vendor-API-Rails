module Api
  module V1
    class ProductsController < ApplicationController
      before_action :authenticate!

      def index
        render_success({ message: "placeholder" })
      end

      def replenish
        render_success({ message: "placeholder" })
      end
    end
  end
end
