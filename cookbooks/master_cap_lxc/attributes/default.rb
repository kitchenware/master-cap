
default[:master_cap_lxc][:chef_url] = "http://opscode-omnibus-packages.s3.amazonaws.com/ubuntu/12.04/x86_64/chef_11.8.0-1.ubuntu.12.04_amd64.deb"
default[:master_cap_lxc][:master_chef_url] = "https://launchpad.net/~bpaquet/+archive/master-chef/+files/master-chef_1.0-5_all.deb"

default[:master_cap_lxc][:lxc_net] = {
  :bridge => "lxcbr0",
  :ip => "10.0.3.1",
  :netmask => "255.255.255.0",
  :network => "10.0.3.0/24",
  :dhcp_range => "10.0.3.2,10.0.3.254",
  :dhcp_max => 253,
}