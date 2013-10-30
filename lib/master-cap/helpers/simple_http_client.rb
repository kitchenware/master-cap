
require 'net/http'
require 'net/https'
require 'json'

class SimpleHttpClient

  def initialize options = {}
    @base_url = options[:base_url] || ""
    @json_mode = options[:json_mode] || false
  end

  def http_req_200 method, url_string, body = "", header_params = {}
    resp = http_req method, url_string, body, header_params
    raise "Wrong return code for #{url_string} : #{resp.code}" unless resp.code == "200"
    return @json_mode && resp['content-type'] == 'application/json' ? JSON.parse(resp.body) : resp.body
  end

  def http_req method, url_string, body = '', header_params = {}
    uri = URI.parse("#{@base_url}#{url_string}")
    http = Net::HTTP.new(uri.host, uri.port)
    if uri.scheme == 'https'
      http.use_ssl = true
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE
    end
    case method
      when :get
        request = Net::HTTP::Get.new(uri.request_uri)
      when :put
        request = Net::HTTP::Put.new(uri.request_uri)
        request.body = body
      when :delete
        request = Net::HTTP::Delete.new(uri.request_uri)
        request.body = body
      when :post
        request = Net::HTTP::Post.new(uri.request_uri)
        request.body = body
      else
        raise "Method not implemented #{method}"
    end
    if uri.userinfo
      s = uri.userinfo.split(':')
      request.basic_auth s[0], s[1]
    end
    header_params.each_pair do |name, value|
      request[name] = value
    end

    http.request(request)
  end

end