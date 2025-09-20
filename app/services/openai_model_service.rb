class OpenaiModelService
  include HTTParty
  
  class Error < StandardError; end

  def initialize(endpoint: nil, access_token: nil)
    @endpoint = endpoint || Setting.openai_endpoint || "https://api.openai.com/v1"
    @access_token = access_token || Setting.openai_access_token
  end

  def fetch_models
    # For local endpoints (like LM Studio), try without auth token first
    if local_endpoint?
      return fetch_models_without_auth if @access_token.blank?
    end
    
    return [] unless @access_token.present?

    begin
      response = HTTParty.get(
        "#{@endpoint}/models",
        headers: headers_for_request,
        timeout: 10
      )

      if response.success?
        models = response.parsed_response.dig("data") || []
        models
          .map { |model| model["id"] }
          .compact
          .sort
          .reject { |model| blacklisted?(model) }
      else
        Rails.logger.warn("Failed to fetch OpenAI models: #{response.code} #{response.message}")
        default_models
      end
    rescue StandardError => e
      Rails.logger.warn("Error fetching OpenAI models: #{e.message}")
      default_models
    end
  end

  def provider_type
    case @endpoint
    when /openai\.com/
      :openai
    when /localhost|127\.0\.0\.1|0\.0\.0\.0|host\.docker\.internal/
      :local
    when /openrouter\.ai/
      :openrouter
    else
      :custom
    end
  end

  def default_models
    case provider_type
    when :openai
      %w[
        gpt-4o
        gpt-4o-mini
        gpt-4-turbo
        gpt-4
        gpt-3.5-turbo
        gpt-3.5-turbo-16k
      ]
    when :local
      %w[
        qwen2.5-0.5b-instruct
        llama-3.2-1b-instruct
        llama-3.2-3b-instruct
        phi-3.5-mini-instruct
        gemma-2-2b-instruct
        mistral-7b-instruct
        llama-3.1-8b-instruct
      ]
    when :openrouter
      %w[
        anthropic/claude-3.5-sonnet
        openai/gpt-4o
        openai/gpt-4o-mini
        google/gemini-pro
        meta-llama/llama-3.1-8b-instruct
        microsoft/wizardlm-2-8x22b
      ]
    else
      %w[gpt-4o-mini gpt-4o gpt-4-turbo]
    end.reject { |model| blacklisted?(model) }
  end

  def current_model
    Setting.openai_model.presence || default_models.first
  end

  def validate_endpoint(endpoint_url)
    return false if endpoint_url.blank?

    begin
      uri = URI.parse(endpoint_url)
      uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
    rescue URI::InvalidURIError
      false
    end
  end

  private

  def local_endpoint?
    provider_type == :local
  end

  def fetch_models_without_auth
    begin
      response = HTTParty.get(
        "#{@endpoint}/models",
        headers: { "Content-Type" => "application/json" },
        timeout: 10
      )

      if response.success?
        models = response.parsed_response.dig("data") || []
        models
          .map { |model| model["id"] }
          .compact
          .sort
          .reject { |model| blacklisted?(model) }
      else
        Rails.logger.warn("Failed to fetch local models: #{response.code} #{response.message}")
        default_models
      end
    rescue StandardError => e
      Rails.logger.warn("Error fetching local models: #{e.message}")
      default_models
    end
  end

  def headers_for_request
    headers = { "Content-Type" => "application/json" }
    headers["Authorization"] = "Bearer #{@access_token}" if @access_token.present?
    headers
  end

  def blacklisted?(model)
    blacklist = Setting.openai_model_blacklist || []
    blacklist.any? { |pattern| model.match?(/#{Regexp.escape(pattern)}/i) }
  end
end