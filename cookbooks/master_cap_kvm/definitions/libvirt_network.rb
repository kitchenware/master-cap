
define :libvirt_network, {
  :address => nil,
  :netmask => nil,
  :bridge => nil,
  :forward => false,
  :bind_physical => nil,
  :disable_stp => nil,
} do

  libvirt_network_params = params

  content = "<network><name>#{libvirt_network_params[:name]}</name><bridge name='#{libvirt_network_params[:bridge]}'/>"
  content += "<forward/>" if libvirt_network_params[:forward]
  content += "<ip address='#{libvirt_network_params[:address]}' netmask='#{libvirt_network_params[:netmask]}'>" if libvirt_network_params[:address] &&  libvirt_network_params[:netmask]
  content += "</ip>" if libvirt_network_params[:address] &&  libvirt_network_params[:netmask]
  content += "</network>"

  execute "create libvirt network #{libvirt_network_params[:name]}" do
    command "echo \"#{content}\" > /tmp/net.xml && virsh net-define /tmp/net.xml && virsh net-autostart #{libvirt_network_params[:name]} && virsh net-start #{libvirt_network_params[:name]} && rm /tmp/net.xml"
    not_if "virsh net-list | fgrep #{libvirt_network_params[:name]} | fgrep active | fgrep -q yes"
  end

  if libvirt_network_params[:bind_physical]

    include_recipe "master_cap_kvm::libvirt_network_hook"

    script = <<-EOF
if [ "$1" = "#{libvirt_network_params[:name]}"  -a "$2" = "started" ]; then
EOF
    if libvirt_network_params[:bind_physical].match(/^([^\.]+)\.([^\.]+)/)
      interface, vlan = $1, $2
      script += <<-EOF
  cat /proc/net/vlan/config | grep #{libvirt_network_params[:bind_physical]} > /dev/null || vconfig add #{interface} #{vlan}
EOF
    end

    script += <<-EOF
  brctl addif #{libvirt_network_params[:bridge]} #{libvirt_network_params[:bind_physical]}
EOF

    script << "  brctl stp #{libvirt_network_params[:bridge]} off\n" if libvirt_network_params[:disable_stp]

script += <<-EOF
  ifconfig #{libvirt_network_params[:bind_physical]} up
fi
EOF

    incremental_template_content "physical_#{libvirt_network_params[:bind_physical]}" do
      target "/etc/libvirt/hooks/network"
      content script
    end

  end

end
