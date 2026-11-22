require "json"
require "net/http"
require "uri"

module LatestStockPrice
  class Client
    def initialize(configuration)
      @configuration = configuration
    end

    def price(symbol)
      value = normalize_symbol(symbol)
      endpoint = endpoint!(:price)
      parameter = endpoint["symbol_param"] || endpoint[:symbol_param]
      raise ConfigurationError, "price endpoint must define symbol_param" if parameter.to_s.empty?

      get(endpoint, [ [ parameter.to_s, value ] ])
    end

    def prices(symbols)
      values = Array(symbols).map { |symbol| normalize_symbol(symbol) }
      raise ConfigurationError, "at least one symbol is required" if values.empty?

      endpoint = endpoint!(:prices)
      parameter = endpoint["symbols_param"] || endpoint[:symbols_param]
      raise ConfigurationError, "prices endpoint must define symbols_param" if parameter.to_s.empty?

      encoding = (endpoint["symbols_encoding"] || endpoint[:symbols_encoding] || :repeated).to_sym
      parameters = if encoding == :comma_separated
        [ [ parameter.to_s, values.join(",") ] ]
      elsif encoding == :repeated
        values.map { |value| [ parameter.to_s, value ] }
      else
        raise ConfigurationError, "symbols_encoding must be repeated or comma_separated"
      end
      get(endpoint, parameters)
    end

    def price_all
      get(endpoint!(:price_all), [])
    end

    private

    attr_reader :configuration

    def normalize_symbol(symbol)
      value = symbol.to_s.strip
      raise ConfigurationError, "symbol must be present" if value.empty?

      value
    end

    def endpoint!(name)
      endpoint = configuration.endpoints[name] || configuration.endpoints[name.to_s]
      raise ConfigurationError, "#{name} endpoint is not configured" unless endpoint.is_a?(Hash)
      raise ConfigurationError, "#{name} endpoint must define path" if (endpoint["path"] || endpoint[:path]).to_s.empty?

      endpoint
    end

    def get(endpoint, supplied_parameters)
      uri = build_uri(endpoint, supplied_parameters)
      request = Net::HTTP::Get.new(uri)
      configured_headers.each { |name, value| request[name.to_s] = value.to_s }
      request[configuration.api_key_header.to_s] = configuration.api_key.to_s if configuration.api_key_header

      response = Net::HTTP.start(
        uri.host,
        uri.port,
        use_ssl: uri.scheme == "https",
        open_timeout: configuration.open_timeout,
        read_timeout: configuration.read_timeout
      ) { |http| http.request(request) }
      raise HttpError, response.code unless response.is_a?(Net::HTTPSuccess)

      JSON.parse(response.body)
    rescue JSON::ParserError
      raise ResponseError, "stock price provider returned invalid JSON"
    rescue Net::OpenTimeout, Net::ReadTimeout, Timeout::Error
      raise TimeoutError, "stock price provider request timed out"
    rescue SocketError, SystemCallError, IOError, Net::HTTPError => error
      raise NetworkError, "stock price provider request failed: #{error.class}"
    end

    def build_uri(endpoint, supplied_parameters)
      base = URI.parse(configuration.base_url.to_s)
      unless %w[http https].include?(base.scheme) && base.host && base.userinfo.nil?
        raise ConfigurationError, "base_url must be an HTTP(S) URL without user information"
      end

      path = endpoint["path"] || endpoint[:path]
      uri = URI.join(configuration.base_url, path.to_s)
      unless uri.host == base.host && uri.scheme == base.scheme && uri.userinfo.nil?
        raise ConfigurationError, "endpoint path must stay on the configured provider host"
      end
      endpoint_parameters = endpoint["params"] || endpoint[:params] || {}
      parameters = endpoint_parameters.to_a + supplied_parameters
      uri.query = URI.encode_www_form(parameters) if parameters.any?
      uri
    rescue URI::InvalidURIError
      raise ConfigurationError, "invalid provider URL"
    end

    def configured_headers
      headers = configuration.headers || {}
      if configuration.api_key_header
        raise ConfigurationError, "configured API key is missing" if configuration.api_key.to_s.empty?
      end
      headers
    end
  end
end
