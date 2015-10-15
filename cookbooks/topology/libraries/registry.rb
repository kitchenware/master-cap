class Registry

  attr_accessor :node

  LAYER_EXTRA_LOW = 10
  LAYER_LOW = 20
  LAYER_STANDARD = 30
  LAYER_HIGH = 40
  LAYER_EXTRA_HIGH = 50
  LAYER_EXTRA_EXTRA_HIGH = 60
  LAYER_MAX = 100000

  def initialize(node)
    @node = node
  end

  def find(name, type, instance = "default", options = {})
  end

  class RegistryUri

    attr_accessor :host, :port, :scheme, :path, :user, :password

    def initialize(uri)
      @host = uri.host
      @port = uri.port
      @scheme = uri.scheme
      @path = CGI.unescape(uri.path)
      @user = CGI.unescape(uri.user) if uri.user
      @password = CGI.unescape(uri.password) if uri.password
    end

    def first_path
      path.split('/')[1]
    end

    def to_uri_no_credentials
      "#{scheme}://#{host}:#{port}#{path}"
    end

    def to_hash
      {:host => host, :port => port, :scheme => scheme, :path => path, :user => user, :password => password}
    end

    def to_s
      to_hash.to_s
    end

  end
end

require 'cgi'

class RegistryMasterCap < Registry

  def initialize(node)
    super(node)
    @cache = {}
  end

  def find(name, type, *args)
    options = {}
    instance = "default"
    if args[0]
      if args[0].is_a? Hash
        options = args[0]
      else
        instance = args[0]
      end
    end

    options = args[1] if args[1]
    key_cache = [name, type, instance, options]
    return @cache[key_cache] if @cache[key_cache]

    key = "#{name}_#{type}_#{instance}"
    registry = @node[:registry][key]
    raise "Missing entry in registry for [#{key}]" unless registry

    max_layer = options[:max_layer] || (LAYER_MAX + 1)
    result = []

    config = Hash[registry.map { |(k, v)| [k.to_sym, v] }]
    if config
      raise "Missing type field in registry configuration for #{key}" unless config[:type]
      begin
        case config[:type].to_sym
          when :interpolated
            if options[:only_one]
              result << {"uri" => eval('"' + config[:string] + '"'), "layer" => LAYER_STANDARD}
            end
          when :mysql
            load_extensions LocalStorage
            load_extensions MysqlHelper
            mysql_conf = mysql_config(config[:id].to_s)
            topology_nodes = find_using_topology(config[:target_role], config[:ip_type], max_layer, options[:only_ip])
            if mysql_conf[:database]
              topology_nodes.each do |topology_node|
                topology_node["id"] = config[:id]
                topology_node["uri"] = "mysql://#{encode(mysql_conf[:username])}:#{encode(mysql_conf[:password])}@#{topology_node["ip"]}:3306/#{mysql_conf[:database]}"
              end
              if topology_nodes.size == 1
                mysql_compute_host config[:id] do
                  topology_nodes.first["ip"]
                end
              end
            else
              topology_nodes.each do |topology_node|
                uri = "mysql://#{topology_node["ip"]}:3306"
                topology_node['id'] = config[:id]
                topology_node['uri'] = uri
              end
            end
            result += topology_nodes
          when :postgresql
            load_extensions LocalStorage
            load_extensions PostgresqlHelper
            postgresql_conf = postgresql_config(config[:id].to_s)
            topology_nodes = find_using_topology(config[:target_role], config[:ip_type], max_layer, options[:only_ip])
            if postgresql_conf[:database]
              topology_nodes.each do |topology_node|
                topology_node["id"] = config[:id]
                topology_node["uri"] = "postgresql://#{encode(postgresql_conf[:username])}:#{encode(postgresql_conf[:password])}@#{topology_node["ip"]}:5432/#{postgresql_conf[:database]}"
              end
            else
              topology_nodes.each do |topology_node|
                uri = "postgresql://#{topology_node["ip"]}:5432"
                topology_node['id'] = config[:id]
                topology_node['uri'] = uri
              end
            end
            result += topology_nodes
          when :url
            url = (config[:target_url] ? config[:target_url].to_sym : nil)
            topology_nodes = find_using_topology(config[:target_role], config[:ip_type], max_layer, options[:only_ip])
            topology_nodes.each do |topology_node|
              uri = format_url(create_url(topology_node["ip"], url)).chomp("/")
              topology_node["uri"] = uri
            end
            result += topology_nodes
          when :object
            result << recurse_interpolate(config[:object].to_hash.dup).merge("layer" => LAYER_STANDARD)
          else
            Chef::Log.warn("Unknown registry type [#{config[:type]}]")
        end
      rescue Exception => e
        Chef::Log.warn("RegistryMasterCap: #{e} when looking for [#{key}]")
        puts e.backtrace
        result = []
      end
    else
      Chef::Log.warn("RegistryMasterCap: No config for #{key}")
    end
    result = recurse_parse_uri result
    if result.size > 1
      result.each do |x|
        raise "Missing hostname field in #{x.inspect}" unless x["hostname"]
      end
      result = result.sort_by { |x| x["hostname"] }
    end

    # Process layering: only keep the results with higher-layer results which is under the max_layer
    result.reject! { |x| x["layer"] > max_layer }
    max = result.map { |x| x["layer"] }.max
    result.reject! { |x| x["layer"] != max }

    # Process only_XXX options
    if options[:only_local]
      result.select! { |x| x["hostname"] == node.hostname }
      raise "No result for request #{key} with role #{config[:target_role]}, only_local specified" if result.empty?
      raise "Too many result for request #{key}with role #{config[:target_role]}, only_local specified" if result.length > 1
      result = result.first
    end
    if options[:only_other]
      result.select! { |x| x["hostname"] != node.hostname }
    end
    if options[:only_one]
      raise "No result for request #{key} with role #{config[:target_role]}, only_one specified" if result.empty?
      raise "Too many result for request #{key} with role #{config[:target_role]}, only_one specified : #{result}" if result.length > 1
      result = result.first
    end
    Chef::Log.info("RegistryMasterCap: find #{key} : #{result.inspect}")
    @cache[key_cache] = result
    result
  end

  def find_vip(vip_name)
    vips = find_localizers_by_role(vip_name.to_sym)
    max = vips.map { |x| x["layer"] }.max
    vips.reject! { |x| x["layer"] != max }
    raise "Vip not found with localizer [#{vip_name}]" if vips.empty?
    raise "Too many vip with localizer [#{vip_name}]" if vips.length > 1
    {:name => vips.first["node_name"], :config => vips.first["node_config"]}
  end

  private

  @@extensions_loaded = []

  def load_extensions clazz
    return if @@extensions_loaded.include? clazz
    self.class.send(:include, clazz)
    @@extensions_loaded << clazz
  end

  def recurse_interpolate(o)
    if o.is_a? Hash
      result = {}
      o.each do |k, v|
        result[k] = recurse_interpolate v
      end
      result
    elsif o.is_a? Array
      o.map { |x| recurse_interpolate x }
    elsif o.is_a? String
      eval('"' + o + '"')
    else
      o
    end
  end

  def find_hostname(n)
    return node.topology[n]["topology_hostname"] if node.topology[n]
    if node[:linked_topologies]
      node.linked_topologies.values.each do |l|
        return l[n]["topology_hostname"] if l[n]
      end
    end
    raise "Unable to find name for #{n}"
  end

  def encode(s)
    CGI.escape(s)
  end

  def recurse_parse_uri(map)
    if map.is_a? Hash
      new_map = {}
      map.each do |k, v|
        new_map[k] = recurse_parse_uri(v)
      end
      new_map["parsed_uri"] = RegistryUri.new(URI.parse(new_map["uri"])) if new_map["uri"]
      new_map
    elsif map.is_a? Array
      map.map { |x| recurse_parse_uri x }
    else
      map
    end
  end

  def find_using_topology(role, ip_type, max_layer, only_ip)
    role = role ? role.to_sym : role
    result = []
    find_nodes_by_role(role).each_pair do |node_name, node_param|
      result << {'hostname' => find_hostname(node_name), 'layer' => LAYER_STANDARD, 'ip' => extract_ip(node_name, node_param, ip_type, only_ip)}
    end
    find_localizers_by_role(role).each do |r|
      if max_layer >= r['layer']
        result << {'hostname' => find_hostname(r['node_name']), 'layer' => r['layer'], 'ip' => extract_ip(r['node_name'], r['node_config'], ip_type, only_ip)}
      end
    end
    result
  end

  def format_url(config)
    "#{config["scheme"]}://#{config["host"]}:#{config["port"]}#{config["path"]}"
  end

  def create_url(ip, url)
    raise "No url definition for [#{url}]" unless node.urls[url]
    config = node.urls[url].to_hash
    config["host"] = ip
    config["path_no_slash"] = config["path"][1..-1]
    config
  end

  def extract_ip(node_name, node_config, ip_type, only_ip)
    c = node_config[:host_ips][ip_type || :user]
    only_ip ? c[:ip] : c[:hostname] || c[:ip]
  end

  def iterate_on_topoloy
    already_done = []
    node.topology.each_pair do |node_name, node_config|
      raise "Duplicated name on topology" if already_done.include? node_name
      already_done << node_name
      yield node_name, node_config
    end
    if node[:linked_topologies]
      node.linked_topologies.values.each do |l|
        l.each_pair do |node_name, node_config|
          raise "Duplicated name on topology" if already_done.include? node_name
          already_done << node_name
          yield node_name, node_config
        end
      end
    end
  end

  def find_localizers_by_role(role)
    nodes = []
    iterate_on_topoloy do |node_name, node_config|
      (node_config[:localizers] || []).each do |r|
        nodes << {'node_name' => node_name, 'layer' => LAYER_HIGH, 'node_config' => node_config} if r.to_sym == role
      end
      (node_config[:layered_localizers] || {}).each do |k, v|
        if k.to_sym == role
          raise "Unable to parse layer #{v}" unless self.class.const_defined? v
          layer = self.class.const_get v
          nodes << {'node_name' => node_name, 'layer' => layer, 'node_config' => node_config}
        end
      end
    end
    nodes
  end

  def find_nodes_by_role(role)
    nodes = {}
    iterate_on_topoloy do |node_name, node_config|
      (node_config[:roles] || []).each do |r|
        nodes[node_name] = node_config if r.to_sym == role
      end
    end
    nodes
  end

end

class Chef
  class Node

    def registry
      @registry ||= RegistryMasterCap.new(self)
    end

  end
end
