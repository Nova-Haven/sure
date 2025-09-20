# Set default URL options for all environments
# This is needed for Turbo broadcasts and other URL generation in background jobs

Rails.application.configure do
  # Set default URL options for route generation
  config.after_initialize do
    Rails.application.routes.default_url_options = {
      host: ENV["APP_DOMAIN"] || "localhost:3000",
      protocol: ENV["APP_PROTOCOL"] || "http"
    }
    
    # Also ensure ActionMailer uses the same host
    unless Rails.application.config.action_mailer.default_url_options&.dig(:host)
      Rails.application.config.action_mailer.default_url_options = {
        host: ENV["APP_DOMAIN"] || "localhost:3000",
        protocol: ENV["APP_PROTOCOL"] || "http"
      }
    end
  end
end