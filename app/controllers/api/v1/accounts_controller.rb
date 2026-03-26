module Api
  module V1
    class AccountsController < ApplicationController
      before_action :authenticate!, except: [:create]

      def create
        render_success({ message: "placeholder" }, :created)
      end

      def me
        render_success({ message: "placeholder" })
      end

      def top_up
        render_success({ message: "placeholder" })
      end
    end
  end
end
