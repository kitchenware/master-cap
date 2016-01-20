
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

  service "apparmor" do
    supports :reload => true
    action [:nothing]
  end

  execute "allow libvirt to access hugespages in apparmor" do
    command "echo 'owner \"/hugepages/libvirt/qemu/**\" rw,' >> /etc/apparmor.d/abstractions/libvirt-qemu"
    not_if "cat /etc/apparmor.d/abstractions/libvirt-qemu | grep hugepages/libvirt/qemu"
    notifies :reload, "service[apparmor]"
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
  command "echo \"#{storage.gsub(/\n/, '')}\" | sed -e \"s/##ID##/$(cat /etc/group | grep libvirt | head -n1 | cut -d: -f3)/\" > /tmp/storage.xml && virsh pool-define /tmp/storage.xml && virsh pool-autostart default && virsh pool-start default && rm /tmp/storage.xml"
  not_if "virsh pool-list | fgrep default | fgrep active | fgrep -q yes"
end

if node.master_cap_kvm.allow_chef_to_use_virsh

  add_user_in_group "chef" do
    group "libvirt"
  end

  file "#{get_home 'chef'}/.bash_profile" do
    owner 'chef'
    content "export LIBVIRT_DEFAULT_URI=qemu:///system"
  end

  service "libvirtd" do
    supports :restart => true
    action [:nothing]
  end

  execute "patch libvirtd.conf for unix_sock_group" do
    command "sed -i 's/^#unix_sock_group/unix_sock_group/' /etc/libvirt/libvirtd.conf"
    only_if "cat /etc/libvirt/libvirtd.conf | grep '#unix_sock_group'"
    notifies :restart, "service[libvirtd]"
  end

  execute "patch libvirtd.conf for auth_unix_rw" do
    command "sed -i 's/^#auth_unix_rw/auth_unix_rw/' /etc/libvirt/libvirtd.conf"
    only_if "cat /etc/libvirt/libvirtd.conf | grep '#auth_unix_rw'"
    notifies :restart, "service[libvirtd]"
  end

end

if node.platform == "debian"

  execute "patch libvirt-guests for parallel shutdown" do
    command "sed -i 's/^.*PARALLEL_SHUTDOWN.*$/PARALLEL_SHUTDOWN=#{node.master_cap_kvm.parallel_shutdown}/' /etc/default/libvirt-guests "
    not_if "cat /etc/default/libvirt-guests | grep PARALLEL_SHUTDOWN | grep #{node.master_cap_kvm.parallel_shutdown}"
  end

end