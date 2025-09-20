class Provider::Openai::ChatParser
  Error = Class.new(StandardError)

  def initialize(object)
    @object = object
  end

  def parsed
    ChatResponse.new(
      id: response_id,
      model: response_model,
      messages: messages,
      function_requests: function_requests
    )
  end

  private
    attr_reader :object

    ChatResponse = Provider::LlmConcept::ChatResponse
    ChatMessage = Provider::LlmConcept::ChatMessage
    ChatFunctionRequest = Provider::LlmConcept::ChatFunctionRequest

    def response_id
      object.dig("id")
    end

    def response_model
      object.dig("model")
    end

    def messages
      # Handle standard OpenAI Chat Completions response format
      choices = object.dig("choices") || []
      
      choices.map do |choice|
        message = choice.dig("message")
        ChatMessage.new(
          id: object.dig("id"), # Use response ID since message doesn't have its own ID
          output_text: message.dig("content") || ""
        )
      end
    end

    def function_requests
      # Handle standard OpenAI function/tool calls
      choices = object.dig("choices") || []
      function_requests = []
      
      choices.each do |choice|
        message = choice.dig("message")
        tool_calls = message.dig("tool_calls") || []
        
        tool_calls.each do |tool_call|
          if tool_call.dig("type") == "function"
            function_requests << ChatFunctionRequest.new(
              id: tool_call.dig("id"),
              call_id: tool_call.dig("id"),
              function_name: tool_call.dig("function", "name"),
              function_args: JSON.parse(tool_call.dig("function", "arguments") || "{}")
            )
          end
        end
      end
      
      function_requests
    end
end
