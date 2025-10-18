class Assistant::Function::GetBalanceSheet < Assistant::Function
  include ActiveSupport::NumberHelper

  class << self
    def name
      "get_balance_sheet"
    end

    def description
      <<~INSTRUCTIONS
        Use this to get the user's balance sheet with varying amounts of historical data.

        This is great for answering questions like:
        - What is the user's net worth?  What is it composed of?
        - How has the user's wealth changed over time?
      INSTRUCTIONS
    end
  end

  def call(params = {})
    begin
      Rails.logger.debug "[GetBalanceSheet] Starting to gather balance sheet data"
      
      # Check if user has any accounts
      if family.accounts.visible.empty?
        Rails.logger.debug "[GetBalanceSheet] No accounts found for user"
        return {
          no_data: true,
          message: "It looks like you don't have any accounts set up yet. Would you like me to guide you through setting up your first account?",
          as_of_date: Date.current,
          currency: family.currency
        }
      end
      
      observation_start_date = [ 5.years.ago.to_date, family.oldest_entry_date ].max

      period = Period.custom(start_date: observation_start_date, end_date: Date.current)
      
      Rails.logger.debug "[GetBalanceSheet] Period set: #{period.start_date} to #{period.end_date}"

      {
        as_of_date: Date.current,
        oldest_account_start_date: family.oldest_entry_date,
        currency: family.currency,
        net_worth: {
          current: family.balance_sheet.net_worth_money.format,
          monthly_history: historical_data(period)
        },
        assets: {
          current: family.balance_sheet.assets.total_money.format,
          monthly_history: historical_data(period, classification: "asset")
        },
        liabilities: {
          current: family.balance_sheet.liabilities.total_money.format,
          monthly_history: historical_data(period, classification: "liability")
        },
        insights: insights_data
      }
    rescue => e
      Rails.logger.error "[GetBalanceSheet] Error: #{e.class} - #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      
      # Return a simpler response that won't cause further issues
      {
        error: true,
        message: "Unable to retrieve balance sheet data. You may need to set up accounts first.",
        as_of_date: Date.current,
        currency: family.currency
      }
    end
  end

  private
    def historical_data(period, classification: nil)
      begin
        scope = family.accounts.visible
        scope = scope.where(classification: classification) if classification.present?
        
        # If no accounts, return empty array
        if scope.count == 0
          Rails.logger.debug "[GetBalanceSheet] No accounts found for classification: #{classification || 'all'}"
          return []
        end

        if period.start_date == Date.current
          []
        else
          account_ids = scope.pluck(:id)
          
          Rails.logger.debug "[GetBalanceSheet] Found #{account_ids.count} accounts for classification: #{classification || 'all'}"

          begin
            builder = Balance::ChartSeriesBuilder.new(
              account_ids: account_ids,
              currency: family.currency,
              period: period,
              favorable_direction: "up",
              interval: "1 month"
            )

            to_ai_time_series(builder.balance_series)
          rescue => e
            Rails.logger.error "[GetBalanceSheet] Error building chart series: #{e.class} - #{e.message}"
            Rails.logger.error e.backtrace.join("\n")
            # Return empty array on failure rather than raising exception
            []
          end
        end
      rescue => e
        Rails.logger.error "[GetBalanceSheet] Error in historical_data: #{e.class} - #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
        # Return empty array on failure rather than raising exception
        []
      end
    end

    def insights_data
      begin
        assets = family.balance_sheet.assets.total
        liabilities = family.balance_sheet.liabilities.total
        ratio = liabilities.zero? ? 0 : (liabilities / assets.to_f)

        {
          debt_to_asset_ratio: number_to_percentage(ratio * 100, precision: 0)
        }
      rescue => e
        Rails.logger.error "[GetBalanceSheet] Error in insights_data: #{e.class} - #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
        # Return placeholder on failure rather than raising exception
        {
          debt_to_asset_ratio: "N/A"
        }
      end
    end
end
