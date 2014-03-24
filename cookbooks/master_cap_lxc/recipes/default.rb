
add_apt_repository "bpaquet_lxc" do
  url "http://ppa.launchpad.net/bpaquet/lxc/ubuntu"
  key "C4832F92"
  key_server "keyserver.ubuntu.com"
end

include_recipe "master_cap_lxc::ksm"

package "lxc"

template "/etc/default/lxc" do
  source "lxc_default.erb"
  variables :lxc_net => node.master_cap_lxc.lxc_net
end

template "/usr/share/lxc/templates/lxc-ubuntu-chef" do
  source node.master_cap_lxc[:ubuntu_chef_template] || "lxc-ubuntu-chef.erb"
  mode '0755'
  variables node.master_cap_lxc
end

template "/etc/sysctl.d/20-inotify.conf" do
  owner 'root'
  group 'root'
  mode '0644'
  notifies :restart, "service[procps]", :immediately
end
