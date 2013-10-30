
require 'master-cap/dns/base_dns'
require 'master-cap/helpers/simple_http_client'

class DnsDnsmasqRestApi < BaseDns

  def initialize cap, params
    @cap = cap
    @params = params
    [:url].each do |x|
      raise "Missing params :#{x}" unless @params.key? x
    end
    @http = SimpleHttpClient.new :base_url => @params[:url], :json_mode => true
  end

  def get_zone_name name
    @params[:zone_override] || name
  end

  def read_current_records name
    l = @http.http_req_200 :get, "/zones/#{name}"
    result = []
    l.each do |ip, aliases|
      aliases.each do |a|
        result << {:ip => ip, :name => a}
      end
    end
    result
  end

  def add_record name, record
    @http.http_req_200 :post, "/zones/#{name}/#{record[:ip]}/#{record[:name]}", '', {'X-Auth-Token' => @params[:write_token]}
  end

  def del_record name, record
    @http.http_req_200 :delete, "/zones/#{name}/#{record[:ip]}/#{record[:name]}", '', {'X-Auth-Token' => @params[:write_token]}
  end

  def reload name
    @http.http_req_200 :post, "/reload", '', {'X-Auth-Token' => @params[:write_token]}
  end

end
