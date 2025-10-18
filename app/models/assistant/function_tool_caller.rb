class Assistant::FunctionToolCaller
  Error = Class.new(StandardError)
  FunctionExecutionError = Class.new(Error)

  attr_reader :functions

  def initialize(functions = [])
    @functions = functions
  end

  def fulfill_requests(function_requests)
    function_requests.map do |function_request|
      Rails.logger.debug "[FunctionToolCaller] Executing function request: #{function_request.function_name}"
      begin
        result = execute(function_request)
        Rails.logger.debug "[FunctionToolCaller] Function executed successfully"
        
        ToolCall::Function.from_function_request(function_request, result)
      rescue => e
        Rails.logger.error "[FunctionToolCaller] Error executing function #{function_request.function_name}: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
        
        # Return a graceful error message that can be displayed to the user
        error_result = {
          error: true,
          message: "I couldn't retrieve your financial data. Please try again or ask a different question."
        }
        ToolCall::Function.from_function_request(function_request, error_result)
      end
    end
  end

  def function_definitions
    functions.map(&:to_definition)
  end

  private
    def execute(function_request)
      fn = find_function(function_request)
      fn_args = JSON.parse(function_request.function_args)
      fn.call(fn_args)
    rescue => e
      raise FunctionExecutionError.new(
        "Error calling function #{fn.name} with arguments #{fn_args}: #{e.message}"
      )
    end

    def find_function(function_request)
      functions.find { |f| f.name == function_request.function_name }
    end
end
