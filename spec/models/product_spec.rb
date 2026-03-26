require "rails_helper"

RSpec.describe Product, type: :model do
  describe "associations" do
    it { should have_many(:orders) }
  end

  describe "validations" do
    it { should validate_presence_of(:name) }
    it { should validate_presence_of(:denomination) }
    it { should validate_numericality_of(:denomination).is_greater_than(0) }
    it { should validate_numericality_of(:stock).is_greater_than_or_equal_to(0) }
    it { should validate_presence_of(:currency) }
  end

  describe "scopes" do
    it "active scope returns only active products" do
      active = create(:product, active: true)
      create(:product, active: false)

      expect(Product.active).to eq([active])
    end
  end
end
