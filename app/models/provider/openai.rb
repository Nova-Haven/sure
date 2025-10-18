class Provider::Openai < Provider
  include LlmConcept

  # Subclass so errors caught in this provider are raised as Provider::Openai::Error
  Error = Class.new(Provider::Error)

  MODELS = %w[gpt-4o gpt-4o-mini gpt-4-turbo gpt-4 gpt-3.5-turbo]

  def initialize(access_token, endpoint: nil)
    @endpoint = endpoint || Setting.openai_endpoint || "https://api.openai.com/v1"
    
    # For local LLM endpoints, the access token might be dummy/not required
    # but the OpenAI client still expects one
    effective_token = access_token.present? ? access_token : "dummy-token"
    
    @client = ::OpenAI::Client.new(
      access_token: effective_token,
      uri_base: @endpoint
    )
  end

  def supports_model?(model)
    # For custom endpoints, we're more permissive about model support
    return true if @endpoint != "https://api.openai.com/v1"
    
    MODELS.include?(model)
  end

  def available_models
    @available_models ||= OpenaiModelService.new(
      endpoint: @endpoint,
      access_token: @client.instance_variable_get(:@access_token)
    ).fetch_models
  end

  def auto_categorize(transactions: [], user_categories: [], model: "")
    with_provider_response do
      raise Error, "Too many transactions to auto-categorize. Max is 25 per request." if transactions.size > 25

      result = AutoCategorizer.new(
        client,
        model: model,
        transactions: transactions,
        user_categories: user_categories
      ).auto_categorize

      log_langfuse_generation(
        name: "auto_categorize",
        model: model,
        input: { transactions: transactions, user_categories: user_categories },
        output: result.map(&:to_h)
      )

      result
    end
  end

  def auto_detect_merchants(transactions: [], user_merchants: [], model: "")
    with_provider_response do
      raise Error, "Too many transactions to auto-detect merchants. Max is 25 per request." if transactions.size > 25

      result = AutoMerchantDetector.new(
        client,
        model: model,
        transactions: transactions,
        user_merchants: user_merchants
      ).auto_detect_merchants

      log_langfuse_generation(
        name: "auto_detect_merchants",
        model: model,
        input: { transactions: transactions, user_merchants: user_merchants },
        output: result.map(&:to_h)
      )

      result
    end
  end

  def chat_response(
    prompt,
    model:,
    instructions: nil,
    functions: [],
    function_results: [],
    streamer: nil,
    previous_response_id: nil,
    session_id: nil,
    user_identifier: nil
  )
    with_provider_response do
      chat_config = ChatConfig.new(
        functions: functions,
        function_results: function_results
      )

      collected_chunks = []

      # Proxy that converts raw stream to "LLM Provider concept" stream
      stream_proxy = if streamer.present?
        proc do |chunk|
          parsed_chunk = ChatStreamParser.new(chunk).parsed

          if parsed_chunk
            Rails.logger.debug "[OpenAI Provider] Got parsed chunk type: #{parsed_chunk.type}"
            streamer.call(parsed_chunk)
            collected_chunks << parsed_chunk
          end
        end
      else
        nil
      end

      messages = chat_config.build_input(prompt)
      
      # Add system message if instructions are provided
      if instructions.present?
        system_content = if instructions.is_a?(String)
          [{ type: "text", text: instructions }]
        else
          instructions
        end
        messages.unshift({ role: "system", content: system_content })
      end

      # Use standard OpenAI Chat Completions API
      raw_response = client.chat(
        parameters: {
          model: model,
          messages: messages,
          tools: chat_config.tools.present? ? chat_config.tools : nil,
          stream: stream_proxy
        }
      )

      # If streaming, Ruby OpenAI does not return anything, so to normalize this method's API, we search
      # for the "response chunk" in the stream and return it (it is already parsed)
      if stream_proxy.present?
        Rails.logger.debug "[OpenAI Provider] Collected #{collected_chunks.size} chunks"
        
        response_chunk = collected_chunks.find { |chunk| chunk.type == "response" }
        text_chunks = collected_chunks.select { |chunk| chunk.type == "output_text" }
        
        Rails.logger.debug "[OpenAI Provider] Found #{text_chunks.size} text chunks and #{response_chunk ? 1 : 0} response chunks"
        
        if response_chunk
          response = response_chunk.data
          Rails.logger.debug "[OpenAI Provider] Using response chunk"
        else
          # Fallback: create a minimal response if no completion chunk was received
          # This can happen with some streaming implementations
          Rails.logger.debug "[OpenAI Provider] No response chunk found, creating fallback response"
          
          # Use any text content we've accumulated
          accumulated_text = text_chunks.map(&:data).join
          
          response = Provider::LlmConcept::ChatResponse.new(
            id: SecureRandom.uuid,
            model: model,
            messages: [Provider::LlmConcept::ChatMessage.new(id: SecureRandom.uuid, output_text: accumulated_text.presence || "")],
            function_requests: []
          )
        end
        
        log_langfuse_generation(
          name: "chat_response",
          model: model,
          input: input_payload,
          output: response.messages.map(&:output_text).join("\n"),
          session_id: session_id,
          user_identifier: user_identifier
        )
        response
      else
        parsed = ChatParser.new(raw_response).parsed
        log_langfuse_generation(
          name: "chat_response",
          model: model,
          input: messages,
          output: parsed.messages.map(&:output_text).join("\n"),
          usage: raw_response["usage"],
          session_id: session_id,
          user_identifier: user_identifier
        )
        parsed
      end
    end
  end

  private
    attr_reader :client

    def langfuse_client
      return unless ENV["LANGFUSE_PUBLIC_KEY"].present? && ENV["LANGFUSE_SECRET_KEY"].present?

      @langfuse_client = Langfuse.new
    end

    def log_langfuse_generation(name:, model:, input:, output:, usage: nil, session_id: nil, user_identifier: nil)
      return unless langfuse_client

      trace = langfuse_client.trace(
        name: "openai.#{name}",
        input: input,
        session_id: session_id,
        user_id: user_identifier
      )
      trace.generation(
        name: name,
        model: model,
        input: input,
        output: output,
        usage: usage,
        session_id: session_id,
        user_id: user_identifier
      )
      trace.update(output: output)
    rescue => e
      Rails.logger.warn("Langfuse logging failed: #{e.message}")
    end
end
