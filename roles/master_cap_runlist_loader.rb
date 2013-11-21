
name "master_cap_runlist_loader"

topology_file = "/opt/master-chef/etc/topology.json"

if File.exist?(topology_file) && ENV['MASTER_CHEF_CONFIG'] && File.exist?(ENV['MASTER_CHEF_CONFIG'])

  Chef::Log.info("Loading roles from #{topology_file} and #{ENV['MASTER_CHEF_CONFIG']}")

  topology = JSON.parse(File.read(topology_file), :symbolize_names => true)
  local = JSON.parse(File.read(ENV['MASTER_CHEF_CONFIG']), :symbolize_names => true)
  if local[:node_config] && local[:node_config][:topology_node_name]
    topology_node_name = local[:node_config][:topology_node_name].to_sym
    if topology[:topology] && topology[:topology][topology_node_name]
      local_node_config = topology[:topology][topology_node_name]
      local_run_list = []
      local_run_list += topology[:default_role_list].map{|x| "role[#{x}]"} if topology[:default_role_list] && !local_node_config[:no_default_role]
      local_run_list += local_node_config[:roles].map{|x| "role[#{x}]"} if local_node_config[:roles]
      local_run_list += local_node_config[:recipes].map{|x| "recipe[#{x}]"} if local_node_config[:recipes]
      Chef::Log.info("Autoloaded runlist " + local_run_list.join(', '))
      run_list(local_run_list)
    end
  end

end