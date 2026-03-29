module Api
  module V1
    class AccountsController < ApplicationController
      before_action :authenticate!, except: [:create]
      before_action :require_admin!, only: [:top_up]

      def create
        account = Account.new(account_params)
        account.save!

        render_success({
          id: account.id,
          name: account.name,
          email: account.email,
          balance: account.balance.to_s,
          api_key: account.api_key
        }, :created)
      end

      def me
        render_success({
          id: current_account.id,
          name: current_account.name,
          email: current_account.email,
          balance: current_account.balance.to_s
        })
      end

      def top_up
        amount = params.require(:amount)
        target = params[:email].present? ? Account.find_by!(email: params[:email]) : current_account
        result = Accounts::TopUpService.call(target, amount)

        render_success({
          email: result[:account].email,
          balance: result[:account].balance.to_s,
          transaction: {
            type: result[:transaction].transaction_type,
            amount: result[:transaction].amount.to_s,
            balance_after: result[:transaction].balance_after.to_s
          }
        })
      rescue ArgumentError => e
        render_error("INVALID_AMOUNT", e.message, :unprocessable_entity)
      end

      private

      def account_params
        params.require(:account).permit(:name, :email)
      end
    end
  end
end
