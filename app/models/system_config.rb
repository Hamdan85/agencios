# frozen_string_literal: true

# Non-sensitive infrastructure config. Secrets live in credentials.
module SystemConfig
  module_function

  def app_host
    host = ENV.fetch("APP_HOST", "http://localhost:3000")
    return host if host.start_with?("http://", "https://")
    "https://#{host}"
  end

  def mailer_from
    ENV.fetch("MAILER_FROM", "agencios <no-reply@agencios.app>")
  end
end
