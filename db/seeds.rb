puts "Seeding admin account..."

admin = Account.find_or_initialize_by(email: "admin@voucher-vendor.test")
if admin.new_record?
  admin.name = "Admin"
  admin.balance = 10_000.0
  admin.admin = true
  admin.save!
  puts "  Admin API key: #{admin.api_key}"
else
  admin.update!(admin: true, balance: [admin.balance, 10_000.0].max)
  puts "  Admin account already exists (key: #{admin.api_key})"
end

puts "Seeding demo user account..."

demo = Account.find_or_initialize_by(email: "demo@voucher-vendor.test")
if demo.new_record?
  demo.name = "Demo User"
  demo.balance = 5_000.0
  demo.save!
  puts "  Demo API key: #{demo.api_key}"
else
  puts "  Demo account already exists (key: #{demo.api_key})"
end

puts "Seeding products..."

products = [
  { name: "Amazon Gift Card", denomination: 100.0, stock: 50 },
  { name: "Flipkart Gift Card", denomination: 250.0, stock: 30 },
  { name: "Myntra Gift Card", denomination: 500.0, stock: 20 },
  { name: "Swiggy Gift Card", denomination: 200.0, stock: 40 },
  { name: "BookMyShow Gift Card", denomination: 150.0, stock: 25 },

  # Test products
  { name: "Test - Always Succeeds", denomination: 100.0, stock: 100, test_behavior: "success" },
  { name: "Test - Always Fails", denomination: 100.0, stock: 100, test_behavior: "failure" },
  { name: "Test - Succeeds After Retries", denomination: 100.0, stock: 100, test_behavior: "pending" },
  { name: "Test - Fails After Retry", denomination: 100.0, stock: 100, test_behavior: "refund" },
]

products.each do |attrs|
  Product.find_or_create_by!(name: attrs[:name]) do |p|
    p.denomination = attrs[:denomination]
    p.stock = attrs[:stock]
    p.test_behavior = attrs[:test_behavior]
  end
end

puts "Seeded #{Product.count} products"
