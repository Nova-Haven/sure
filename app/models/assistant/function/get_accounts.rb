class Assistant::Function::GetAccounts < Assistant::Function
  class << self
    def name
      "get_accounts"
    end

    def description
      "Use this to see what accounts the user has along with their current and historical balances"
    end
  end

  def call(params = {})
    begin
      Rails.logger.debug "[GetAccounts] Starting to gather account data"
      
      # Check if there are any accounts
      accounts = family.accounts.visible.includes(:balances)
      
      if accounts.empty?
        return {
          as_of_date: Date.current,
          accounts: [],
          no_accounts: true,
          message: "You don't have any accounts set up yet."
        }
      end
      
      {
        as_of_date: Date.current,
        accounts: accounts.map do |account|
          {
            name: account.name,
            balance: account.balance,
            currency: account.currency,
            balance_formatted: account.balance_money.format,
            classification: account.classification,
            type: account.accountable_type,
            start_date: account.start_date,
            is_plaid_linked: account.plaid_account_id.present?,
            status: account.status,
            historical_balances: historical_balances(account)
          }
        end
      }
    rescue => e
      Rails.logger.error "[GetAccounts] Error: #{e.class} - #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      
      # Return a simpler response that won't cause further issues
      {
        as_of_date: Date.current,
        accounts: [],
        error: true,
        message: "I couldn't retrieve your accounts at this time."
      }
    end
  end

  private
    def historical_balances(account)
      start_date = [ account.start_date, 5.years.ago.to_date ].max
      period = Period.custom(start_date: start_date, end_date: Date.current)
      balance_series = account.balance_series(period: period, interval: "1 month")

      to_ai_time_series(balance_series)
    end
end
