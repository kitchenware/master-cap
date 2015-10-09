
incremental_template "/etc/libvirt/hooks/network" do
  mode '0755'
  header <<-EOF
#!/bin/bash -e

(
echo "Libvirt network hook called with params $@"

EOF
  footer <<-EOF

#{node.master_cap_kvm[:libvirt_network_hook_footer]}

echo "Libvirt network hook end with params $@"
) | logger -t libvirt_network_hook

EOF
  owner "root"
end
