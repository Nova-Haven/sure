class AssistantMessage < Message
  validates :ai_model, presence: true

  after_create :clear_chat_errors
  
  def role
    "assistant"
  end

  def append_text!(text)
    self.content += text
    save!
  end
  
  private
  
  def clear_chat_errors
    # Explicitly clear any error state when an assistant message is created
    chat.clear_error if chat.error.present?
  end
end
