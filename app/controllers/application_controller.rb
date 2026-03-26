class ApplicationController < ActionController::API
  rate_limit to: ENV.fetch("RATE_LIMIT_RPM", 60).to_i, within: 1.minute,
             by: -> { request.headers["Authorization"] || request.remote_ip },
             with: -> { render_error("RATE_LIMITED", "Rate limit exceeded. Try again shortly.", :too_many_requests) }

  rescue_from ActiveRecord::RecordNotFound do |e|
    render_error("NOT_FOUND", e.message, :not_found)
  end

  rescue_from ActiveRecord::RecordInvalid do |e|
    render_error("INVALID_INPUT", e.record.errors.full_messages.join(", "), :unprocessable_entity)
  end

  rescue_from ActionController::ParameterMissing do |e|
    render_error("INVALID_INPUT", e.message, :unprocessable_entity)
  end

  private

  def render_success(data, status = :ok)
    render json: { status: "SUCCESS", data: data }, status: status
  end

  def render_error(code, message, status = :unprocessable_entity)
    render json: { status: "ERROR", error: { code: code, message: message } }, status: status
  end

  def authenticate!
    api_key = request.headers["Authorization"]&.delete_prefix("Bearer ")
    @current_account = Account.find_by(api_key: api_key) if api_key.present?

    unless @current_account
      render_error("UNAUTHORIZED", "Invalid or missing API key", :unauthorized)
    end
  end

  def require_admin!
    render_error("FORBIDDEN", "Admin access required", :forbidden) unless current_account&.admin?
  end

  def current_account
    @current_account
  end
end
