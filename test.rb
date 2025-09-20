#!/usr/bin/env ruby

# This is a test file to check Ruby syntax errors
# Run with: ruby test.rb

puts "Testing Ruby syntax..."

# Let's check if our files have syntax errors
files_to_check = [
  "app/models/assistant/function/get_income_statement.rb",
  "app/models/assistant/function/get_transactions.rb",
  "app/models/assistant/function/get_accounts.rb",
  "app/models/assistant/function/get_user_info.rb"
]

files_to_check.each do |file|
  puts "Checking #{file}..."
  result = system("ruby -c #{file}")
  puts result ? "OK" : "ERROR!"
end

puts "Done."