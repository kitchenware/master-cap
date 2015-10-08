
package "qemu-kvm"
package "libvirt-bin"

include_recipe "master_cap_lxc::ksm"

unless node.master_cap_kvm.hugepages == "disable"

  if node.master_cap_kvm.hugepages == "auto"
    nr_hugepages = (node["memory"]["total"].delete("kB").to_i / 1024 / 2 * node.master_cap_kvm.hugepages_ratio).to_i
  else
    nr_hugepages = node.master_cap_kvm.hugepages
  end

  template "/etc/sysctl.d/10-hugepages.conf" do
    mode '0644'
    notifies :restart, "service[procps]", :immediately
    variables :nr_hugepages => nr_hugepages
  end

  directory "/hugepages" do
    owner "root"
    group "root"
    mode "0755"
  end

  mount "/hugepages" do
    action [:enable]
    device "hugetlbfs"
    device_type :device
    fstype "hugetlbfs"
  end

  execute "mount-hugetlbfs" do
    command "mount -t hugetlbfs hugetlbfs /hugepages"
    not_if  "mount | grep -q hugetlbfs"
  end

end

storage = <<-EOF
<pool type='dir'>
  <name>default</name>
  <source>
  </source>
  <target>
    <path>#{node.master_cap_kvm.tank}</path>
    <permissions>
      <mode>0770</mode>
      <owner>0</owner>
      <group>##ID##</group>
    </permissions>
  </target>
</pool>
EOF

execute "create default pool" do
  command "echo \"#{storage.gsub(/\n/, '')}\" | sed -e \"s/##ID##/$(getent group libvirtd | cut -d: -f3)/\" > /tmp/storage.xml && virsh pool-define /tmp/storage.xml && virsh pool-autostart default && virsh pool-start default && rm /tmp/storage.xml"
  not_if "virsh pool-list | fgrep default | fgrep active | fgrep -q yes"
end

service "apparmor" do
  supports :reload => true
  action [:nothing]
end

execute "allow libvirt to access hugespages in apparmor" do
  command "echo 'owner \"/hugepages/libvirt/qemu/**\" rw,' >> /etc/apparmor.d/abstractions/libvirt-qemu"
  not_if "cat /etc/apparmor.d/abstractions/libvirt-qemu | grep hugepages/libvirt/qemu"
  notifies :reload, "service[apparmor]"
end
