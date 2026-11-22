require_relative "latest_stock_price/configuration"

module LatestStockPrice
  class Error < StandardError; end
  class ConfigurationError < Error; end
  class HttpError < Error
    attr_reader :status

    def initialize(status)
      @status = status.to_i
      super("stock price provider returned HTTP #{@status}")
    end
  end
  class ResponseError < Error; end
  class TimeoutError < Error; end
  class NetworkError < Error; end
end

require_relative "latest_stock_price/client"

module LatestStockPrice
  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration)
      configuration
    end

    def reset_configuration!
      @configuration = Configuration.new
    end

    def price(symbol)
      client.price(symbol)
    end

    def prices(symbols)
      client.prices(symbols)
    end

    def price_all
      client.price_all
    end

    private

    def client
      Client.new(configuration)
    end
  end
end
