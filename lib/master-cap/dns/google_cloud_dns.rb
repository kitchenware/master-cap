
require_relative './base_dns'

class DnsGoogleCloudDns < BaseDns

  def initialize cap, params
    @cap = cap
    @params = params
    config =  TOPOLOGY[cap.check_only_one_env][:hypervisors]
    @fog_params = config["gce"][:params] if config["gce"]

    raise "You should have a gce config in hypervisors to use this" unless config["gce"]

    require 'fog'

    ::Excon.defaults[:ssl_verify_peer] = false if ENV["DISABLE_SSL_VERIFY"]
    [:google_project, :google_client_email, :google_json_key_location].each do |x|
      @cap.error "Missing params :#{x}" unless @fog_params.key? x
    end
    [:domain, :zone].each do |x|
      raise "Missing params :#{x}" unless @params.key? x
    end
  end

  def connection
    @connection ||= Fog::DNS::Google.new(@fog_params)
  end

  def get_zone_name name
    @params[:zone] || name
  end

  def domain name
    connection.zones.get(name).domain
  end

  def ensure_exists list, no_dry
    run list, no_dry do |real_zone_name, current, l|
      modified = false
      l.each do |x|
        unless x[:name].include?(".internal")
          unless current.find{|xx| xx[:ip] == x[:ip] && xx[:name] == "#{x[:name]}.#{domain(real_zone_name)}"}
            puts "Adding record in zone #{real_zone_name} : #{x[:name]}.#{domain(real_zone_name)} : #{x[:ip]}"
            add_record real_zone_name, x if no_dry
            modified = true
          end
        end
      end
      modified
    end
  end

  def ensure_not_exists list, no_dry
    run list, no_dry do |real_zone_name, current, l|
      modified = false
      l.each do |x|
        unless x[:name].include?(".internal")
          if current.find{|xx| xx[:ip] == x[:ip] && xx[:name] == "#{x[:name]}.#{domain(real_zone_name)}"}
            puts "Removing record in zone #{real_zone_name} : #{x[:name]}.#{domain(real_zone_name)} : #{x[:ip]}"
            del_record real_zone_name, x if no_dry
            modified = true
          end
        end
      end
      modified
    end
  end

  def read_current_records name
    l = connection.zones.get(name).records
    result = []
    l.each do |record|
      if record.type == "A"
        result << {:ip => record.rrdatas.first, :name => record.name }
      end
    end
    result
  end

  def add_record name, record
    unless record[:name].include?(".internal")
      zone = connection.zones.get(name)
      zone.records.create(name: "#{record[:name]}.#{domain(name)}", type: 'A', ttl: 360, rrdatas: ["#{record[:ip]}"])
    end
  end

  def del_record name, record
    zone = connection.zones.get(name)
    found_record = zone.records.get("#{record[:name]}.#{domain(name)}", 'A')
    found_record.destroy if record
    raise "Record not found" unless record
  end

  def reload name
    puts "Nothing to do for reload in google cloud dns"
  end

end
