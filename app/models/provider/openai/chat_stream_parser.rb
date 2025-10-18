class Provider::Openai::ChatStreamParser
  Error = Class.new(StandardError)

  def initialize(object)
    @object = object
    
    # Debug logging for streaming responses
    Rails.logger.debug "[ChatStreamParser] Received chunk: #{object.inspect}"
  end

  def parsed
    # Handle standard OpenAI streaming format
    if object.is_a?(Hash) && object.dig("choices")
      # This is a streaming chunk from OpenAI/LM Studio
      choices = object.dig("choices") || []
      
      Rails.logger.debug "[ChatStreamParser] Parsing choices: #{choices.inspect}"
      
      choices.each do |choice|
        delta = choice.dig("delta")
        finish_reason = choice.dig("finish_reason")
        
        # Check for content in delta (streaming case)
        if delta && delta.dig("content").present?
          content = delta.dig("content")
          Rails.logger.debug "[ChatStreamParser] Found delta content: #{content}"
          return Chunk.new(type: "output_text", data: content)
        # Check for content directly in the message (non-streaming case)
        elsif choice.dig("message", "content").present?
          content = choice.dig("message", "content")
          Rails.logger.debug "[ChatStreamParser] Found message content: #{content}"
          return Chunk.new(type: "output_text", data: content)
        # Check for completion
        elsif finish_reason && (finish_reason == "stop" || finish_reason == "length" || finish_reason == "tool_calls")
          Rails.logger.debug "[ChatStreamParser] Found completion with finish_reason: #{finish_reason}"
          # Response completed - construct minimal response for parser
          final_response = {
            "id" => object.dig("id"),
            "model" => object.dig("model"),
            "choices" => [
              {
                "message" => {
                  "content" => "", # Content is accumulated separately in the Assistant
                  "role" => "assistant"
                }
              }
            ]
          }
          return Chunk.new(type: "response", data: parse_response(final_response))
        end
      end
    end
    
    # Handle custom event types (for compatibility with other formats)
    type = object.dig("type")
    case type
    when "response.output_text.delta", "response.refusal.delta"
      Chunk.new(type: "output_text", data: object.dig("delta"))
    when "response.completed"
      raw_response = object.dig("response")
      Chunk.new(type: "response", data: parse_response(raw_response))
    end
    
    # Return nil if we can't parse this chunk (this is normal for some chunks)
    nil
  end

  private
    attr_reader :object

    Chunk = Provider::LlmConcept::ChatStreamChunk

    def parse_response(response)
      Provider::Openai::ChatParser.new(response).parsed
    end
end
