class Provider::Openai::ChatConfig
  def initialize(functions: [], function_results: [])
    @functions = functions
    @function_results = function_results
  end

  def tools
    functions.map do |fn|
      {
        type: "function",
        function: {
          name: fn[:name],
          description: fn[:description],
          parameters: fn[:params_schema],
          strict: fn[:strict]
        }
      }
    end
  end

  def build_input(prompt)
    results = function_results.map do |fn_result|
      {
        type: "function_call_output",
        call_id: fn_result[:call_id],
        output: fn_result[:output].to_json
      }
    end

    # Format content properly for OpenAI-compatible APIs that require type field
    content = if prompt.is_a?(String)
      [{ type: "text", text: prompt }]
    else
      prompt
    end

    [
      { role: "user", content: content },
      *results
    ]
  end

  private
    attr_reader :functions, :function_results
end
