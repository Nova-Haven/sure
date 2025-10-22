class Settings::HostingsController < ApplicationController
  layout "settings"

  guard_feature unless: -> { self_hosted? }

  before_action :ensure_admin, only: [ :update, :clear_cache ]

  def show
    @breadcrumbs = [
      [ "Home", root_path ],
      [ "Self-Hosting", nil ]
    ]
    twelve_data_provider = Provider::Registry.get_provider(:twelve_data)
    @twelve_data_usage = twelve_data_provider&.usage
  end

  def update
    if hosting_params.key?(:require_invite_for_signup)
      Setting.require_invite_for_signup = hosting_params[:require_invite_for_signup]
    end

    if hosting_params.key?(:require_email_confirmation)
      Setting.require_email_confirmation = hosting_params[:require_email_confirmation]
    end

    if hosting_params.key?(:brand_fetch_client_id)
      Setting.brand_fetch_client_id = hosting_params[:brand_fetch_client_id]
    end

    if hosting_params.key?(:twelve_data_api_key)
      Setting.twelve_data_api_key = hosting_params[:twelve_data_api_key]
    end

    if hosting_params.key?(:openai_access_token)
      token_param = hosting_params[:openai_access_token].to_s.strip
      # Ignore blanks and redaction placeholders to prevent accidental overwrite
      unless token_param.blank? || token_param == "********"
        Setting.openai_access_token = token_param
      end
    end

    # Validate OpenAI configuration before updating
    if hosting_params.key?(:openai_uri_base) || hosting_params.key?(:openai_model)
      # Only validate if we're not just setting the URI base to fetch models
      # Skip validation if model is empty and we're setting URI base (user might be fetching models)
      unless hosting_params[:openai_model] == "" && hosting_params.key?(:openai_uri_base)
        Setting.validate_openai_config!(
          uri_base: hosting_params[:openai_uri_base],
          model: hosting_params[:openai_model]
        )
      end
    end

    if hosting_params.key?(:openai_uri_base)
      Setting.openai_uri_base = hosting_params[:openai_uri_base]
    end

    if hosting_params.key?(:openai_model)
      Rails.logger.info "Updating OpenAI model from #{Setting.openai_model} to #{hosting_params[:openai_model]}"
      Setting.openai_model = hosting_params[:openai_model]
      Rails.logger.info "OpenAI model after update: #{Setting.openai_model}"
    end

    redirect_to settings_hosting_path, notice: t(".success")
  rescue Setting::ValidationError => error
    flash.now[:alert] = error.message
    render :show, status: :unprocessable_entity
  end

  def openai_models
    service = OpenaiModelService.new(
      endpoint: params[:endpoint],
      access_token: params[:access_token]
    )
    
    models = service.fetch_models
    
    # Store models in session for next page load
    session[:openai_models] = models
    
    Rails.logger.debug "Fetched models: #{models.inspect}"
    
    render json: { 
      models: models,
      provider_type: service.provider_type
    }
  rescue StandardError => e
    Rails.logger.error "Error fetching models: #{e.message}"
    # Store default models in session even on error
    default_models = service.default_models
    session[:openai_models] = default_models
    
    render json: { 
      error: e.message,
      models: default_models 
    }, status: :unprocessable_entity
  end

  def clear_cache
    DataCacheClearJob.perform_later(Current.family)
    redirect_to settings_hosting_path, notice: t(".cache_cleared")
  end

  private
    def hosting_params
      params.require(:setting).permit(:require_invite_for_signup, :require_email_confirmation, :brand_fetch_client_id, :twelve_data_api_key, :openai_access_token, :openai_uri_base, :openai_model, :openai_model_blacklist, :ai_assistant_name)
    end

    def ensure_admin
      redirect_to settings_hosting_path, alert: t(".not_authorized") unless Current.user.admin?
    end
end
