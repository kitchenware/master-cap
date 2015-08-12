
require_relative 'base'
require_relative '../helpers/ssh_helper'

class HypervisorOpenstack < Hypervisor

  include SshHelper

  def initialize cap, params
    super(cap, params)
    require 'fog'
    ::Excon.defaults[:ssl_verify_peer] = false if ENV["DISABLE_SSL_VERIFY"]
    @params = params
    [:keystone_url, :username, :tenant, :password].each do |x|
      @cap.error "Missing params :#{x}" unless @params.key? x
    end
    @options = {
      :provider => 'openstack',
      :openstack_auth_url => @params[:keystone_url],
      :openstack_username => @params[:username],
      :openstack_tenant => @params[:tenant],
      :openstack_api_key => @params[:password],
    }
    @options[:openstack_region] = @params[:region] if @params[:region]
  end

  def nova
    @nova ||= Fog::Compute.new(@options)
  end

  def neutron
    @neutron ||= Fog::Network.new(@options)
  end

  def flavors
    @flavors ||= nova.flavors.to_a
  end

  def images
    @images ||= nova.images.to_a
  end

  def networks
    @networks ||= neutron.list_networks.body['networks']
  end

  def read_list
    nova.list_servers.body['servers'].map{|x| x['name']}
  end

  def add_network name, cidr
    network = neutron.networks.create(:name => name)
    subnet = neutron.subnets.create(:name => "#{name}_subnet", :network_id => network.id, :cidr => cidr, :ip_version => 4)
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
      config[:flavor_ref] = flavor_ref.id
      image_ref = images.find{|x| x.name == config[:image]}
      raise "Unkown image #{config[:image]}" unless image_ref
      config[:image_ref] = image_ref.id
      if config[:networks]
        config[:nics] = []
        config[:networks].each do |nn|
          network_ref = networks.find{|x| x['name'] == nn}
          raise "Unkown network #{config[:network]}" unless network_ref
          config[:nics] << {:net_id => network_ref['id']}
        end
      end
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
      vm = nova.servers.create(config)
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
        wait_ssh public_ip(vm), user
      end
    end
    puts "Done."
  end

  def delete_vms l, no_dry
    return unless no_dry
    to_be_wait = []
    nova.servers.each do |x|
      l.each do |name, vm|
        if x.name == name
          puts "Deleting #{name}"
          nova.delete_server x.id
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
  end

  def read_topology env
    res = {}
    nova.list_servers_detail.body['servers'].each do |x|
      if x['metadata'] && x['metadata']['env'] == env
        n = {
          :public_hostname => public_ip(x),
          :private_ip => private_ip(x),
        }
        n[:type] = x['metadata']['type'] if x['metadata']['type']
        n[:roles] = JSON.parse(x['metadata']['roles']) if x['metadata']['roles']
        n[:recipes] = JSON.parse(x['metadata']['recipes']) if x['metadata']['recipes']
        n[:node_override] = JSON.parse(x['metadata']['node_override']) if x['metadata']['node_override']
        res[x['metadata']['name']] = n
      end
    end
    res
  end

  private

  def addr_obj server
    return server['addresses'] if server.is_a? Hash
    server.addresses
  end

  def public_ip server
    addr_obj(server)[addr_obj(server).keys[0]].first["addr"]
  end

  def private_ip server
    return nil unless addr_obj(server).keys.size > 1
    addr_obj(server)[addr_obj(server).keys[1]].first["addr"]
  end

end
