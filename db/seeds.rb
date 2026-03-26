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
  { name: "Test - Stays Pending", denomination: 100.0, stock: 100, test_behavior: "pending" },
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
