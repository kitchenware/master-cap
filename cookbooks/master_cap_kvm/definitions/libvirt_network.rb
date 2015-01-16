
define :libvirt_network, {
  :address => nil,
  :netmask => nil,
  :bridge => nil,
  :forward => false,
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

end
