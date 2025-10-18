#!/usr/bin/env ruby
# This is a standalone test script for LM Studio integration
# Run it with: docker compose exec web ruby lm_studio_test.rb

require_relative 'config/environment'

puts "=" * 80
puts "LM Studio Integration Test"
puts "=" * 80

# Get a user to work with
user = User.first
puts "Using user: #{user.email}"

# Create a new test chat
chat = user.chats.create!(title: "LM Studio Test #{Time.current.strftime("%Y%m%d%H%M%S")}")
puts "Created chat: #{chat.id}"

# Create a user message
message = chat.messages.create!(
  content: "Hello! Tell me a joke about programming.",
  type: "UserMessage",
  ai_model: "qwen3-4b-2507" # Make sure this matches your LM Studio model
)
puts "Created message: #{message.id}"

# Process the message directly without the job
puts "Processing message directly..."
puts "-" * 80

begin
  # Skip the job queue and directly call the assistant
  chat.ask_assistant(message)
  puts "Processing completed successfully!"
  
  # Check results
  puts "-" * 80
  puts "Chat error state: #{chat.error.inspect}"
  
  # Get all messages in the chat
  puts "Chat messages:"
  chat.messages.order(:created_at).each do |msg|
    puts "#{msg.type} (#{msg.created_at}): #{msg.content.truncate(100)}"
  end
  
  puts "-" * 80
  puts "Test completed successfully!"
rescue => e
  puts "ERROR: #{e.class} - #{e.message}"
  puts e.backtrace.join("\n")
  puts "-" * 80
  puts "Test failed with error!"
end