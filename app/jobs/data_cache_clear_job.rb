class DataCacheClearJob < ApplicationJob
  queue_as :low_priority

  def perform(family)
    ActiveRecord::Base.transaction do
      ExchangeRate.delete_all
      Security::Price.delete_all
      family.accounts.each do |account|
        account.balances.delete_all
        account.holdings.delete_all
      end
      
      # Schedule a background job to import all market data from the earliest transaction date
      import_market_data_from_earliest_date(family)
      
      family.sync_later
    end
  end
  
  private
  
    def import_market_data_from_earliest_date(family)
      # Find the earliest entry date for the family
      oldest_date = family.oldest_entry_date
      
      # Schedule the market data import job to run with full history
      ImportMarketDataJob.perform_later({
        mode: :full,
        clear_cache: true,
        start_date: oldest_date.to_s
      })
    end
end
