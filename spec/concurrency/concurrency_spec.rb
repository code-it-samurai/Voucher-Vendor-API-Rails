require "rails_helper"

RSpec.describe "Concurrency Safety", type: :model do
  # Disable transactional fixtures - threads need real transactions
  self.use_transactional_tests = false

  after do
    # Manual cleanup since we disabled transactional fixtures
    TransactionRecord.delete_all
    Voucher.delete_all
    Order.delete_all
    Product.delete_all
    Account.delete_all
  end

  def run_concurrently(count = 2, &block)
    threads = count.times.map do |i|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          block.call(i)
        end
      end
    end
    threads.map(&:value)
  end

  describe "duplicate reference_code" do
    it "creates only one order when two threads use same reference_code" do
      account = Account.create!(name: "Test", email: "dup@test.com", balance: 1000.0)
      product = Product.create!(name: "Card", denomination: 100.0, stock: 10)

      params = { product_id: product.id, quantity: 1, denomination: 100.0, reference_code: "DUP-REF" }

      results = run_concurrently(2) do |_i|
        Orders::PlacementService.call(account, params)
      rescue => e
        e
      end

      orders = results.map { |r| r.is_a?(Hash) ? r[:order] : nil }.compact
      expect(orders.map(&:id).uniq.size).to eq(1)
      expect(Order.where(reference_code: "DUP-REF").count).to eq(1)
      expect(account.reload.balance).to eq(900.0)
      expect(product.reload.stock).to eq(9)
    end
  end

  describe "balance exhaustion" do
    it "only one order succeeds when balance is insufficient for both" do
      account = Account.create!(name: "Test", email: "bal@test.com", balance: 150.0)
      product = Product.create!(name: "Card", denomination: 100.0, stock: 10)

      results = run_concurrently(2) do |i|
        params = { product_id: product.id, quantity: 1, denomination: 100.0, reference_code: "BAL-#{i}" }
        Orders::PlacementService.call(account, params)
      rescue Orders::PlacementService::InsufficientBalanceError
        :insufficient
      end

      successes = results.count { |r| r.is_a?(Hash) }
      failures = results.count { |r| r == :insufficient }

      expect(successes).to eq(1)
      expect(failures).to eq(1)
      expect(account.reload.balance).to eq(50.0)
    end
  end

  describe "stock exhaustion" do
    it "only one order succeeds when stock is insufficient for both" do
      account1 = Account.create!(name: "A1", email: "s1@test.com", balance: 1000.0)
      account2 = Account.create!(name: "A2", email: "s2@test.com", balance: 1000.0)
      product = Product.create!(name: "Card", denomination: 100.0, stock: 1)

      results = run_concurrently(2) do |i|
        acct = i == 0 ? account1 : account2
        params = { product_id: product.id, quantity: 1, denomination: 100.0, reference_code: "STK-#{i}" }
        Orders::PlacementService.call(acct, params)
      rescue Orders::PlacementService::OutOfStockError
        :out_of_stock
      end

      successes = results.count { |r| r.is_a?(Hash) }
      failures = results.count { |r| r == :out_of_stock }

      expect(successes).to eq(1)
      expect(failures).to eq(1)
      expect(product.reload.stock).to eq(0)
    end
  end

  describe "concurrent top-ups" do
    it "final balance equals sum of all top-ups" do
      account = Account.create!(name: "Test", email: "topup@test.com", balance: 0.0)

      run_concurrently(5) do |_i|
        Accounts::TopUpService.call(account, 100.0)
      end

      expect(account.reload.balance).to eq(500.0)
      expect(TransactionRecord.where(account: account).count).to eq(5)
    end
  end

  describe "concurrent replenishments" do
    it "final stock equals sum of all replenishments" do
      product = Product.create!(name: "Card", denomination: 100.0, stock: 0)

      run_concurrently(5) do |_i|
        ActiveRecord::Base.transaction do
          p = Product.lock.find(product.id)
          p.update!(stock: p.stock + 10)
        end
      end

      expect(product.reload.stock).to eq(50)
    end
  end
end
