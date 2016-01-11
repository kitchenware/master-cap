
topology_file = "/opt/master-chef/etc/topology.json"

if File.exist? topology_file

  Chef::Log.info("Loading topology from #{topology_file}")

  topology = JSON.parse(File.read(topology_file), :symbolize_names => true)
  node.set[:topology] = topology[:topology]
  node.set[:linked_topologies] = topology[:linked_topologies] if topology[:linked_topologies]
  node.set[:apps] = topology[:apps] if topology[:apps]

  if topology[:node_override]
    topology[:node_override].each do |k, v|
      if v.class == Mash
        node.set[k] = (node[k] || {}).to_hash.deep_merge(v)
      else
        node.set[k] = v
      end
    end
  end

end

if node[:topology_node_name]
  node_config = node[:topology][node[:topology_node_name]]
  if node_config && node_config[:node_override]
    node_config[:node_override].to_hash.each do |k, v|
      if v.is_a? Mash
        node.override[k] = (node[k] || {}).to_hash.deep_merge(v)
      else
        node.override[k] = v
      end
    end
  end
end

if node[:roles_override]
  node.roles.each do |role|
    if node[:roles_override][role]
      node[:roles_override][role].to_hash.each do |k, v|
        if v.is_a? Mash
          node.override[k] = (node[k] || {}).to_hash.deep_merge(v)
        else
          node.override[k] = v
        end
      end
    end
  end
end

default[:registry] = {}
default[:urls] = {}