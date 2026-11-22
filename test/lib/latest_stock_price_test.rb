require "test_helper"
require "net/http"

class LatestStockPriceTest < ActiveSupport::TestCase
  setup do
    LatestStockPrice.reset_configuration!
    LatestStockPrice.configure do |config|
      config.base_url = "https://stocks.example.test"
      config.endpoints = {
        price: { path: "/v1/price", symbol_param: "ticker" },
        prices: { path: "/v1/prices", symbols_param: "tickers", symbols_encoding: :repeated },
        price_all: { path: "/v1/all" }
      }
      config.headers = { "X-Client" => "test" }
      config.open_timeout = 1
      config.read_timeout = 1
    end
  end

  teardown do
    LatestStockPrice.reset_configuration!
  end

  test "price, prices, and price_all issue configured GET requests and return parsed JSON" do
    requests = []
    bodies = [ '{"ticker":"AAPL","price":210.50}', '{"tickers":["AAPL","MSFT"]}', '[{"ticker":"AAPL"}]' ]
    test_case = self
    with_http do |http|
      http.define_singleton_method(:request) do |request|
        requests << request
        test_case.send(:response_for, bodies.fetch(requests.length - 1))
      end

      assert_equal({ "ticker" => "AAPL", "price" => 210.50 }, LatestStockPrice.price("AAPL"))
      assert_equal({ "tickers" => [ "AAPL", "MSFT" ] }, LatestStockPrice.prices(%w[AAPL MSFT]))
      assert_equal [ { "ticker" => "AAPL" } ], LatestStockPrice.price_all
      assert_equal "/v1/price?ticker=AAPL", requests[0].path
      assert_equal "/v1/prices?tickers=AAPL&tickers=MSFT", requests[1].path
      assert_equal "/v1/all", requests[2].path
      assert requests.all? { |request| request["X-Client"] == "test" }
    end
  end

  test "non-success status and malformed JSON raise typed errors" do
    with_http_response(status: "429", body: "rate limited") do
      assert_raises(LatestStockPrice::HttpError) { LatestStockPrice.price("AAPL") }
    end
    with_http_response(status: "200", body: "not json") do
      assert_raises(LatestStockPrice::ResponseError) { LatestStockPrice.price("AAPL") }
    end
  end

  test "timeouts raise a typed error and invalid symbols are rejected before HTTP" do
    with_http_start(->(*) { raise Net::ReadTimeout }) do
      assert_raises(LatestStockPrice::TimeoutError) { LatestStockPrice.price("AAPL") }
    end
    assert_raises(LatestStockPrice::ConfigurationError) { LatestStockPrice.price(" ") }
  end

  test "missing configured API key is rejected and unknown-symbol JSON is returned unchanged" do
    LatestStockPrice.configuration.api_key_header = "X-Provider-Key"
    assert_raises(LatestStockPrice::ConfigurationError) { LatestStockPrice.price("AAPL") }

    LatestStockPrice.configuration.api_key_header = nil
    with_http_response(status: "200", body: '{"error":"unknown symbol"}') do
      assert_equal({ "error" => "unknown symbol" }, LatestStockPrice.price("NOTREAL"))
    end
  end

  private

  def with_http_response(status:, body:)
    test_case = self
    with_http do |http|
      http.define_singleton_method(:request) { |_request| test_case.send(:response_for, body, status: status) }
      yield
    end
  end

  def with_http
    fake_http = Object.new
    with_http_start(->(*, **, &request_block) { request_block.call(fake_http) }) { yield(fake_http) }
  end

  def with_http_start(implementation)
    original = Net::HTTP.method(:start)
    Net::HTTP.singleton_class.define_method(:start, implementation)
    yield
  ensure
    Net::HTTP.singleton_class.define_method(:start, original)
  end

  def response_for(body, status: "200")
    response_class = status.to_i.between?(200, 299) ? Net::HTTPOK : Net::HTTPTooManyRequests
    response = response_class.new("1.1", status, "OK")
    response.instance_variable_set(:@read, true)
    response.instance_variable_set(:@body, body)
    response
  end
end
