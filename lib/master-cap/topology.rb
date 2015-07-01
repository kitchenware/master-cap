
require_relative 'topologies/directory'

TOPOLOGY = {}

Capistrano::Configuration.instance.load do

  set :chef_role, fetch(:chef_role, :linux_chef)
  set :user, fetch(:user, "chef")

  task :check do
    find_nodes(:roles => chef_role).sort_by{|env, node, s| s.host}.each do |env, node|
      begin
        exec_local_with_timeout "ssh -o StrictHostKeyChecking=no #{user}@#{node[:topology_hostname]} uname > /dev/null 2>&1", fetch(:check_timeout, 10)
        puts "OK    : #{node[:topology_hostname]}"
      rescue
        puts "ERROR : Unable to join #{node[:topology_hostname]}"
      end
    end
  end

  task :ssh_cmd, :roles => chef_role do
    error "Please specify command with -s cmd=" unless exists? :cmd
    run cmd
  end

  task :show do
    ss = find_nodes
    puts "Number of selected servers: #{ss.length}"
    ss = ss.sort_by do |item|
      item[1][:capistrano_name]
    end
    ss.each do |env, node|
      puts "#{fill(node[:capistrano_name], 30)} #{fill(node[:admin_hostname], 50)} [#{((node[:roles] || []) + (node[:recipes] || [])).sort.join(',')}]"
    end
  end

  task :json do
    env = check_only_one_env
    File.open("#{env}.json", 'w') {|io| io.write(JSON.pretty_generate(TOPOLOGY[env]))}
    puts "File written #{env}.json"
  end

  task :ssh do
    find_servers.map{|s| s.host}.each do |s|
      exec_local "ssh #{user}@#{s}"
    end
  end

  def find_node node_name
    TOPOLOGY.each do |k, v|
      v[:topology].each do |name, node|
        return [k, node] if get_translation_strategy(k).ip(:admin, name)[:hostname] == node_name
      end
    end
    error "Node not found #{node_name}"
  end

  def find_nodes filter = {}
    find_servers(filter).map do |s|
      env, node = find_node(s.host)
      [env, node, s]
    end
  end

  def check_only_one_env servers = nil, allow_empty_env = false
    servers = find_servers unless servers
    env_list = {}
    servers.each do |s|
      env, name, node = find_node(s.is_a?(String) ? s : s.host)
      env_list[env] = :toto
    end
    unless allow_empty_env && env_list.keys.size == 0
      error "Please, do not launch this command without env" if env_list.keys.size == 0
      error "Please, do not launch this command on two env : #{env_list.keys.join(' ')}" if env_list.keys.size != 1
      env = env_list.keys.first
    else
      error "Multiple env detected" if TOPOLOGY.keys.size > 1
      error "No env detected" if TOPOLOGY.keys.size == 0
      env = TOPOLOGY.keys.first
    end

    check_only_one_env_callback[:proc].call(env, servers) if exists? :check_only_one_env_callback

    env
  end

  def get_translation_strategy env
    TOPOLOGY[env][:translation_strategy]
  end

end
