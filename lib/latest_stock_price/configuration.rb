module LatestStockPrice
  class Configuration
    attr_accessor :base_url, :endpoints, :headers, :api_key, :api_key_header,
      :open_timeout, :read_timeout

    def initialize
      @endpoints = {}
      @headers = {}
      @open_timeout = 3
      @read_timeout = 5
    end
  end
end
