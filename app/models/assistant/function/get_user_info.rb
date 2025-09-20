class Assistant::Function::GetUserInfo < Assistant::Function
  class << self
    def name
      "get_user_info"
    end

    def description
      <<~INSTRUCTIONS
        Use this to get general information about the user's profile and account. 
        This is useful when the user asks for their "info" or general account details.
      INSTRUCTIONS
    end
    
    # Debug method for testing
    def debug_test(family_id)
      puts "DEBUG: Testing GetUserInfo with family_id: #{family_id}"
      begin
        family = Family.find(family_id)
        puts "DEBUG: Found family: #{family.name}"
        instance = new(family)
        puts "DEBUG: Created instance"
        result = instance.call
        puts "DEBUG: Result: #{result.inspect}"
        return "Success: #{result.class}"
      rescue => e
        puts "DEBUG ERROR: #{e.class} - #{e.message}"
        puts e.backtrace.join("\n")
        return "Error: #{e.class} - #{e.message}"
      end
    end
  end

  def call(params = {})
    begin
      Rails.logger.debug "[GetUserInfo] Starting to gather user data"
      
      # Check if the user has any accounts
      has_accounts = family.accounts.visible.any?
      
      # Get basic account information
      account_stats = {
        total_accounts: family.accounts.visible.count,
        linked_accounts: family.accounts.visible.where.not(plaid_account_id: nil).count,
        manual_accounts: family.accounts.visible.where(plaid_account_id: nil).count
      }
      
      # Get transaction info
      transaction_stats = if has_accounts
        {
          total_transactions: family.transactions.count,
          categorized_transactions: family.transactions.where.not(category_id: nil).count,
          earliest_transaction: family.transactions.order(date: :asc).first&.date || "N/A",
          latest_transaction: family.transactions.order(date: :desc).first&.date || "N/A"
        }
      else
        {
          total_transactions: 0,
          categorized_transactions: 0,
          earliest_transaction: "N/A",
          latest_transaction: "N/A"
        }
      end
      
      # Return user profile data
      {
        user: {
          name: "#{user.first_name} #{user.last_name}".strip,
          email: user.email,
          created_at: user.created_at,
          account_age_days: (Date.current - user.created_at.to_date).to_i,
          preferred_currency: family.currency
        },
        accounts: account_stats,
        transactions: transaction_stats,
        has_data: family.accounts.visible.any?
      }
    rescue => e
      Rails.logger.error "[GetUserInfo] Error: #{e.class} - #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      
      # Return a simpler response that won't cause further issues
      {
        error: true,
        message: "I couldn't retrieve your account information at this time.",
        has_data: false
      }
    end
  end
end