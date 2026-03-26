class Account < ApplicationRecord
  has_many :orders, dependent: :restrict_with_error
  has_many :transaction_records, dependent: :restrict_with_error

  validates :name, presence: true
  validates :email, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :api_key, presence: true, uniqueness: true
  validates :balance, numericality: { greater_than_or_equal_to: 0 }

  before_validation :generate_api_key, on: :create

  private

  def generate_api_key
    return if api_key.present?

    secret = ENV.fetch("API_KEY_SECRET", "default_dev_secret")
    self.api_key = OpenSSL::HMAC.hexdigest("SHA256", secret, email.to_s)
  end
end
