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

    if hosting_params.key?(:openai_endpoint)
      endpoint_param = hosting_params[:openai_endpoint].to_s.strip
      if endpoint_param.present? && OpenaiModelService.new.validate_endpoint(endpoint_param)
        Setting.openai_endpoint = endpoint_param
      end
    end

    if hosting_params.key?(:openai_model)
      model_param = hosting_params[:openai_model].to_s.strip
      Setting.openai_model = model_param if model_param.present?
    end

    if hosting_params.key?(:openai_model_blacklist)
      blacklist = hosting_params[:openai_model_blacklist]&.reject(&:blank?) || []
      Setting.openai_model_blacklist = blacklist
    end

    redirect_to settings_hosting_path, notice: t(".success")
  rescue ActiveRecord::RecordInvalid => error
    flash.now[:alert] = t(".failure")
    render :show, status: :unprocessable_entity
  end

  def openai_models
    service = OpenaiModelService.new(
      endpoint: params[:endpoint],
      access_token: params[:access_token]
    )
    
    models = service.fetch_models
    
    render json: { 
      models: models,
      provider_type: service.provider_type
    }
  rescue StandardError => e
    render json: { 
      error: e.message,
      models: service.default_models 
    }, status: :unprocessable_entity
  end

  def clear_cache
    DataCacheClearJob.perform_later(Current.family)
    redirect_to settings_hosting_path, notice: t(".cache_cleared")
  end

  private
    def hosting_params
      params.require(:setting).permit(
        :require_invite_for_signup, 
        :require_email_confirmation, 
        :brand_fetch_client_id, 
        :twelve_data_api_key, 
        :openai_access_token,
        :openai_endpoint,
        :openai_model,
        openai_model_blacklist: []
      )
    end

    def ensure_admin
      redirect_to settings_hosting_path, alert: t(".not_authorized") unless Current.user.admin?
    end
end
