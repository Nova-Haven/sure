class Assistant::Responder
  def initialize(message:, instructions:, function_tool_caller:, llm:)
    @message = message
    @instructions = instructions
    @function_tool_caller = function_tool_caller
    @llm = llm
  end

  def on(event_name, &block)
    listeners[event_name.to_sym] << block
  end

  def respond(previous_response_id: nil)
    # Track whether response was handled by streamer
    response_handled = false

    # For the first response
    streamer = proc do |chunk|
      case chunk.type
      when "output_text"
        emit(:output_text, chunk.data)
      when "response"
        response = chunk.data
        response_handled = true

        if response.function_requests.any?
          handle_follow_up_response(response)
        else
          emit(:response, { id: response.id })
        end
      end
    end

    response = get_llm_response(streamer: streamer, previous_response_id: previous_response_id)

    # For synchronous (non-streaming) responses, handle function requests if not already handled by streamer
    unless response_handled
      if response && response.function_requests.any?
        handle_follow_up_response(response)
      elsif response
        emit(:response, { id: response.id })
      end
    end
  end

  private
    attr_reader :message, :instructions, :function_tool_caller, :llm

    def handle_follow_up_response(response)
      streamer = proc do |chunk|
        case chunk.type
        when "output_text"
          emit(:output_text, chunk.data)
        when "response"
          # We do not currently support function executions for a follow-up response (avoid recursive LLM calls that could lead to high spend)
          emit(:response, { id: chunk.data.id })
        end
      end

      function_tool_calls = function_tool_caller.fulfill_requests(response.function_requests)

      emit(:response, {
        id: response.id,
        function_tool_calls: function_tool_calls
      })

      # Get follow-up response with tool call results
      get_llm_response(
        streamer: streamer,
        function_results: function_tool_calls.map(&:to_result),
        previous_response_id: response.id
      )
    end
    
    def get_llm_response(streamer:, function_results: [], previous_response_id: nil)
      Rails.logger.debug "[Assistant::Responder] Getting LLM response with function_results: #{function_results.inspect}"
      Rails.logger.debug "[Assistant::Responder] LLM: #{llm.class.name}"

      response = llm.chat_response(
        message.content,
        model: message.ai_model,
        instructions: instructions,
        functions: function_tool_caller.function_definitions,
        function_results: function_results,
        streamer: streamer,
        previous_response_id: previous_response_id,
        session_id: chat_session_id,
        user_identifier: chat_user_identifier
      )

      unless response.success?
        Rails.logger.error "[Assistant::Responder] LLM response error: #{response.error.class} - #{response.error.message}"
        Rails.logger.error response.error.backtrace.join("\n") if response.error.respond_to?(:backtrace)
        raise response.error
      end

      Rails.logger.debug "[Assistant::Responder] Got successful LLM response"
      response.data
    rescue => e
      Rails.logger.error "[Assistant::Responder] Error getting LLM response: #{e.class} - #{e.message}"
      Rails.logger.error e.backtrace.join("\n") if e.respond_to?(:backtrace)
      raise e
    end
    
    def emit(event_name, payload = nil)
      listeners[event_name.to_sym].each { |block| block.call(payload) }
    end

    def listeners
      @listeners ||= Hash.new { |h, k| h[k] = [] }
    end

    def chat_session_id
      chat&.id&.to_s
    end

    def chat_user_identifier
      return unless chat&.user_id

      ::Digest::SHA256.hexdigest(chat.user_id.to_s)
    end

    def chat
      @chat ||= message.chat
    end
end
