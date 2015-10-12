
define :libvirt_network, {
  :address => nil,
  :netmask => nil,
  :bridge => nil,
  :forward => false,
  :bind_physical => nil,
  :disable_stp => true,
  :default_gateway => nil,
} do

  libvirt_network_params = params

  content = "<network><name>#{libvirt_network_params[:name]}</name><bridge name='#{libvirt_network_params[:bridge]}' stp='#{libvirt_network_params[:disable_stp] ? 'off' : 'on'}'/>"
  content += "<forward/>" if libvirt_network_params[:forward]
  content += "<ip address='#{libvirt_network_params[:address]}' netmask='#{libvirt_network_params[:netmask]}'>" if libvirt_network_params[:address] &&  libvirt_network_params[:netmask]
  content += "</ip>" if libvirt_network_params[:address] &&  libvirt_network_params[:netmask]
  content += "</network>"

  if libvirt_network_params[:bind_physical]

    include_recipe "master_cap_kvm::libvirt_network_hook"

    script = <<-EOF
if [ "$1" = "#{libvirt_network_params[:name]}"  -a "$2" = "started" ]; then
EOF
    if libvirt_network_params[:bind_physical].match(/^([^\.]+)\.([^\.]+)/)
      interface, vlan = $1, $2
      script += <<-EOF
  modprobe 8021q
  echo "Checking interface #{libvirt_network_params[:bind_physical]}"
  cat /proc/net/vlan/config | grep #{libvirt_network_params[:bind_physical]} > /dev/null || vconfig add #{interface} #{vlan}
  echo "Mouting sub interface"
  ifconfig #{interface} up
EOF
    end

    script += <<-EOF
  echo "Adding #{libvirt_network_params[:bind_physical]} to #{libvirt_network_params[:bridge]}"
  brctl addif #{libvirt_network_params[:bridge]} #{libvirt_network_params[:bind_physical]}
EOF

    if libvirt_network_params[:disable_stp]
      script << <<-EOF
  echo "Disabling stp on #{libvirt_network_params[:bridge]}"
  brctl stp #{libvirt_network_params[:bridge]} off
EOF
    end

script += <<-EOF
  echo "Starting interface #{libvirt_network_params[:bind_physical]}"
  ifconfig #{libvirt_network_params[:bind_physical]} up
fi
EOF

    if libvirt_network_params[:default_gateway]
      script << <<-EOF
  if ip route show | grep default > /dev/null; then
    echo "Skipping add of default gateway #{libvirt_network_params[:default_gateway]}"
  else
    echo "Adding default gateway to #{libvirt_network_params[:default_gateway]}"
    ip route add default via #{libvirt_network_params[:default_gateway]}
  fi
EOF
    end

    incremental_template_content "physical_#{libvirt_network_params[:bind_physical]}" do
      target "/etc/libvirt/hooks/network"
      content script
    end

  end

  execute "create libvirt network #{libvirt_network_params[:name]}" do
    command "echo \"#{content}\" > /tmp/net.xml && virsh net-define /tmp/net.xml && virsh net-autostart #{libvirt_network_params[:name]} && virsh net-start #{libvirt_network_params[:name]} && rm /tmp/net.xml"
    not_if "virsh net-list | fgrep #{libvirt_network_params[:name]} | fgrep active | fgrep -q yes"
  end

end
