class Provider
  Response = Data.define(:success?, :data, :error)

  class Error < StandardError
    attr_reader :details

    def initialize(message, details: nil)
      super(message)
      @details = details
    end

    def as_json
      {
        message: message,
        details: details
      }
    end
  end

  private
    PaginatedData = Data.define(:paginated, :first_page, :total_pages)
    UsageData = Data.define(:used, :limit, :utilization, :plan)

    def with_provider_response(error_transformer: nil, &block)
      Rails.logger.debug "[Provider] Starting with_provider_response"
      begin
        data = yield
        Rails.logger.debug "[Provider] Successfully got data from block"

        Response.new(
          success?: true,
          data: data,
          error: nil,
        )
      rescue => error
        Rails.logger.error "[Provider] Error in with_provider_response: #{error.class} - #{error.message}"
        Rails.logger.error error.backtrace.join("\n")
        
        transformed_error = if error_transformer
          error_transformer.call(error)
        else
          default_error_transformer(error)
        end

        Rails.logger.error "[Provider] Transformed error: #{transformed_error.class} - #{transformed_error.message}"

        Response.new(
          success?: false,
          data: nil,
          error: transformed_error
        )
      end
    end

    # Override to set class-level error transformation for methods using `with_provider_response`
    def default_error_transformer(error)
      if error.is_a?(Faraday::Error)
        self.class::Error.new(
          error.message,
          details: error.response&.dig(:body),
        )
      else
        self.class::Error.new(error.message)
      end
    end
end
