
require_relative 'base'
require_relative '../helpers/ssh_helper'

class HypervisorGce < Hypervisor

  include SshHelper

  def initialize cap, params
    super(cap, params)
    require 'fog'
    @params = params
    [:google_project, :google_client_email, :google_json_key_location].each do |x|
      @cap.error "Missing params :#{x}" unless @params.key? x
    end
    @options = {
      :provider => 'google',
      :google_project => @params[:google_project],
      :google_client_email => @params[:google_client_email],
      :google_json_key_location => @params[:google_json_key_location],
    }
  end

  def connection
    @connection ||= Fog::Compute.new(@options)
  end

  def flavors
    @flavors ||= connection.flavors.all
  end

  def pretty_flavors
    flavor_list = []
    zones = []
    flavors.each do |f|
      flavor = {}
      flavor[:name] = f.name
      flavor[:zone] = f.zone
      zones << f.zone
      flavor[:description] = f.description
      flavor_list << flavor
    end

    uniq_zones = zones.uniq

    uniq_zones.each do |zone|
      zone_flavors = []
      flavor_list.each do |f|
        zone_flavors << f if f[:zone] == zone
      end
      puts "Zone : #{zone}"
      zone_flavors.each do |f|
        puts "\t #{f[:name]} : #{f[:description]}"
      end
    end
  end

  def images
    @images ||= connection.images.all
  end

  def networks
    @networks ||= connection.networks.all
  end

  def read_list
    connection.servers.all.map{|x| x.name }
  end

  def server_list
    connection.servers.all
  end

  def create_new env, default, translation_strategy
    raise "Please specify template_topology_file" unless @cap.exists?(:template_topology_file)
    raise "Please specify nodes" unless @cap.exists?(:nodes)
    raise "Please specify templates" unless @cap.exists?(:templates)

    yaml = YAML.load(File.read("topology/#{@cap.fetch(:template_topology_file)}.yml"))
    topology = yaml[:topology]
    default_role_list = yaml[:default_role_list]
    nodes = @cap.fetch(:nodes).split(',')
    templates = @cap.fetch(:templates).split(',')
    vms = []
    ssh_wait = []
    nodes.each_with_index do |n, k|
      name = translation_strategy.vm_name n
      template = topology[templates[k].to_sym] || topology[templates[k]]
      raise "Missing template #{templates[k]}" unless template
      puts "Creating node #{name} from #{templates[k]}"
      config = default.merge(template[:vm] || {})
      raise "No flavor specified" unless config[:flavor]
      raise "No image specified" unless config[:image]
      config[:name] = name
      flavor_ref = flavors.find{|x| x.name == config[:flavor]}
      raise "Unkown flavor #{config[:flavor]}" unless flavor_ref
      config[:machine_type] = flavor_ref.name
      image_ref = images.find{|x| x.name == config[:image]}
      raise "Unkown image #{config[:image]}" unless image_ref
      disk = connection.disks.create({
        :name => "#{n}-#{env}",
        :size_gb => config[:disk_size],
        :zone_name => config[:zone_name],
        :source_image => image_ref.name,
        :autoDelete => true,
      })

      disk.wait_for { disk.ready? }

      config[:disks] = [disk.get_as_boot_disk(true)]
      if config[:network]
        network_ref = networks.find{|x| x.name == config[:network]}
        config[:network] = network_ref.name
      end
      config[:tags] = env
      config['metadata'] = {}
      config['metadata']['env'] = env
      config['metadata']['name'] = n
      config['metadata']['type'] = template[:type] if template[:type]
      if File.exist?("roles/#{env}.rb")
        customer_role = [env]
      else
        customer_role = []
      end
      config['metadata']['roles'] = JSON.dump(default_role_list + template[:roles] + customer_role) if template[:roles]
      config['metadata']['recipes'] = JSON.dump(template[:recipes]) if template[:recipes]
      config['metadata']['node_override'] = JSON.dump(template[:node_override]) if template[:node_override]
      vm = connection.servers.create(config)
      vm.set_scheduling 'MIGRATE', true, false
      vms << vm
      ssh_wait << [config[:ssh_user], vm] if config[:ssh_user]
    end
    puts "Waiting all vms ready"
    while true
      ok = true
      vms.each do |vm|
        vm.reload
        ok &= vm.ready?
      end
      break if ok
      sleep 5
    end
    unless ssh_wait.empty?
      puts "Waiting ssh for all vms"
      ssh_wait.each do |user, vm|
        puts "Waiting #{vm.name}, #{public_ip(vm)}"
        wait_ssh public_ip(vm), user, 90
      end
    end
    puts "Done."
  end

  def delete_vms l, no_dry
    return unless no_dry
    to_be_wait = []
    disk_to_delete = []
    connection.servers.each do |x|
      l.each do |name, vm|
        if x.name == name
          puts "Deleting #{name}"
          x.destroy
          disk_to_delete << name
          to_be_wait << x
        end
      end
    end
    while true
      ok = true
      to_be_wait.each do |x|
        res = false
        begin
          x.reload.state
        rescue
          res = true
        end
        ok &= res
      end
      break if ok
      sleep 5
    end
    disk_to_delete.each do |dname|
      connection.disks.find {|disk| disk.name == dname }.destroy
    end
  end

  def read_topology env
    res = {}
    server_list.each do |x|
      if x.metadata &&  linked_to_env?(x, env)
        n = {
          :public_hostname => x.network_interfaces.first['accessConfigs'].first['natIP'],
          :private_ip => x.network_interfaces.first['networkIP'],
        }
        n[:type] = get_metadatas x, "type"
        n[:roles] = JSON.parse(get_metadatas(x, "roles")) if get_metadatas(x, "roles")
        n[:recipes] = JSON.parse(get_metadatas(x, "recipes")) if get_metadatas(x, "recipes")
        n[:node_override] = JSON.parse(get_metadatas(x, "node_override")) if get_metadatas(x, "node_override")
        res[x.name] = n
      end
    end
    res
  end

  private

  def linked_to_env? server, envt
    return unless server.metadata["items"]
    return unless server.name.include?(envt)
    metadatas_items = server.metadata["items"]
    vm_env = metadatas_items.find {|item| item["key"] == "env"}
    vm_env["value"] == envt
  end

  def get_metadatas server, key
    metadatas_items = server.metadata["items"]
    meta = metadatas_items.find {|item| item["key"] == key}
    return meta["value"] if meta
    return nil
  end

  def addr_obj server
    return server['addresses'] if server.is_a? Hash
    server.addresses
  end

  def public_ip server
    addr_obj(server)[1]
  end

  def private_ip server
    return nil unless addr_obj(server).size == 1
    addr_obj(server)[0]
  end

end
