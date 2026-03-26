module AuthHelper
  def auth_headers(account)
    { "Authorization" => "Bearer #{account.api_key}" }
  end
end

RSpec.configure do |config|
  config.include AuthHelper, type: :request
end
