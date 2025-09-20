class Assistant::Function::GetInvestmentPortfolio < Assistant::Function
  class << self
    def name
      "get_investment_portfolio"
    end

    def description
      <<~INSTRUCTIONS
        Use this to get information about the user's investment portfolio and securities.
        This is useful when the user asks about their investments, stocks, funds, or portfolio performance.
      INSTRUCTIONS
    end
  end

  def call(params = {})
    begin
      Rails.logger.debug "[GetInvestmentPortfolio] Starting to gather investment data"

      # Check if there are any securities
      security_accounts = family.accounts.visible.where(accountable_type: ["Securities"])
      
      if security_accounts.empty?
        return {
          no_securities: true,
          message: "You don't have any investment accounts set up yet.",
          as_of_date: Date.current,
          currency: family.currency
        }
      end
      
      # Gather investment account data
      investment_accounts = security_accounts.map do |account|
        {
          name: account.name,
          balance: account.balance,
          currency: account.currency,
          balance_formatted: account.balance_money.format,
          account_number: account.account_number,
          status: account.status
        }
      end
      
      # Get portfolio summary
      portfolio_value = security_accounts.sum(&:balance)
      portfolio_formatted = Money.new(portfolio_value, family.currency).format
      
      {
        as_of_date: Date.current,
        currency: family.currency,
        portfolio_value: portfolio_formatted,
        accounts: investment_accounts,
        account_count: investment_accounts.size
      }
    rescue => e
      Rails.logger.error "[GetInvestmentPortfolio] Error: #{e.class} - #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      
      # Return a simpler response that won't cause further issues
      {
        error: true,
        message: "I couldn't retrieve your investment portfolio at this time.",
        as_of_date: Date.current,
        currency: family.currency
      }
    end
  end
end