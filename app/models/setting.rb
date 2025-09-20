# Dynamic settings the user can change within the app (helpful for self-hosting)
class Setting < RailsSettings::Base
  cache_prefix { "v1" }

  field :twelve_data_api_key, type: :string, default: ENV["TWELVE_DATA_API_KEY"]
  field :openai_access_token, type: :string, default: ENV["OPENAI_ACCESS_TOKEN"]
  field :openai_endpoint, type: :string, default: ENV.fetch("OPENAI_ENDPOINT", "https://api.openai.com/v1")
  field :openai_model, type: :string, default: ENV.fetch("OPENAI_MODEL", "qwen2.5-0.5b-instruct")
  field :openai_model_blacklist, type: :array, default: ["embedding", "whisper"]
  field :brand_fetch_client_id, type: :string, default: ENV["BRAND_FETCH_CLIENT_ID"]

  field :require_invite_for_signup, type: :boolean, default: false
  field :require_email_confirmation, type: :boolean, default: ENV.fetch("REQUIRE_EMAIL_CONFIRMATION", "true") == "true"
end
