require "test_helper"

class OpenaiModelServiceTest < ActiveSupport::TestCase
  def setup
    @service = OpenaiModelService.new
    Setting.openai_model_blacklist = []
  end

  test "validates endpoint URLs correctly" do
    assert @service.validate_endpoint("https://api.openai.com/v1")
    assert @service.validate_endpoint("http://localhost:1234/v1")
    assert @service.validate_endpoint("https://openrouter.ai/api/v1")
    
    assert_not @service.validate_endpoint("")
    assert_not @service.validate_endpoint("not-a-url")
    assert_not @service.validate_endpoint("ftp://example.com")
  end

  test "identifies provider types correctly" do
    openai_service = OpenaiModelService.new(endpoint: "https://api.openai.com/v1")
    assert_equal :openai, openai_service.provider_type

    local_service = OpenaiModelService.new(endpoint: "http://localhost:1234/v1")
    assert_equal :local, local_service.provider_type

    openrouter_service = OpenaiModelService.new(endpoint: "https://openrouter.ai/api/v1")
    assert_equal :openrouter, openrouter_service.provider_type

    custom_service = OpenaiModelService.new(endpoint: "https://custom.example.com/v1")
    assert_equal :custom, custom_service.provider_type
  end

  test "returns appropriate default models for each provider" do
    openai_service = OpenaiModelService.new(endpoint: "https://api.openai.com/v1")
    openai_models = openai_service.default_models
    assert_includes openai_models, "gpt-4o"
    assert_includes openai_models, "gpt-4o-mini"

    local_service = OpenaiModelService.new(endpoint: "http://localhost:1234/v1")
    local_models = local_service.default_models
    assert_includes local_models, "llama-3.1-8b-instruct"

    openrouter_service = OpenaiModelService.new(endpoint: "https://openrouter.ai/api/v1")
    openrouter_models = openrouter_service.default_models
    assert_includes openrouter_models, "anthropic/claude-3.5-sonnet"
  end

  test "applies blacklist filtering to default models" do
    Setting.openai_model_blacklist = ["gpt-3.5", "embedding"]
    
    service = OpenaiModelService.new(endpoint: "https://api.openai.com/v1")
    models = service.default_models
    
    assert_not_includes models, "gpt-3.5-turbo"
    assert_not_includes models, "gpt-3.5-turbo-16k"
    assert_includes models, "gpt-4o"
  end

  test "blacklist filtering is case insensitive" do
    Setting.openai_model_blacklist = ["GPT-3.5"]
    
    service = OpenaiModelService.new(endpoint: "https://api.openai.com/v1")
    models = service.default_models
    
    assert_not_includes models, "gpt-3.5-turbo"
  end

  test "fetch_models returns default models when no access token" do
    service = OpenaiModelService.new(access_token: nil)
    models = service.fetch_models
    
    assert_equal service.default_models, models
  end

  test "current_model returns Setting value or first default" do
    Setting.openai_model = "gpt-4o"
    service = OpenaiModelService.new
    assert_equal "gpt-4o", service.current_model

    Setting.openai_model = nil
    assert_equal service.default_models.first, service.current_model
  end
end