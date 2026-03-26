require "rails_helper"

RSpec.describe Voucher, type: :model do
  describe "associations" do
    it { should belong_to(:order) }
  end

  describe "validations" do
    subject { build(:voucher) }

    it { should validate_presence_of(:code) }
    it { should validate_uniqueness_of(:code) }
  end
end
