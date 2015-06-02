
require_relative 'base'
require_relative '../helpers/ssh_helper'

class HypervisorKvm < Hypervisor

  include SshHelper

  def initialize cap, params
    super(cap, params)
    @params = params
    [:kvm_user, :kvm_host, :kvm_sudo].each do |x|
      @cap.error "Missing params :#{x}" unless @params.key? x
    end
    @ssh = SshDriver.new @params[:kvm_host], @params[:kvm_user], @params[:kvm_sudo]
  end

  def read_list
    res = @ssh.capture("virsh list --all").split("\n")
    res.shift
    res.shift
    res = res.map{|x| x.match(/^\s*\S+\s+(\S+)/)[1]}
    res
  end

  def start_vms l, no_dry
    return unless no_dry
    l.each do |name, vm|
      puts "Starting #{name}"
      @ssh.exec "virsh start #{name}"
      wait_ssh vm[:hostname], @cap.fetch(:user)
    end
  end

  def stop_vms l, no_dry
    return unless no_dry
    l.each do |name, vm|
      puts "Stopping #{name}"
      @ssh.exec "virsh destroy #{name}"
    end
  end

  def default_vm_config
    @params[:default_vm]
  end

  def create_vms l, no_dry
    return unless no_dry
    l.each do |name, vm|
      user = @cap.fetch(:user)
      ssh_keys = vm[:vm][:ssh_keys]
      vol_source = vm[:vm][:vol_source]
      machine_type = vm[:vm][:machine_type] || "pc-1.3"
      pool = vm[:vm][:pool] || "default"
      hugespages = vm[:vm][:use_hugepages] || true
      ip_config = vm[:host_ips][:internal] || vm[:host_ips][:admin]
      network_gateway = vm[:vm][:network_gateway]
      network_netmask = vm[:vm][:network_netmask]
      network_bridge = vm[:vm][:network_bridge]
      network_dns = vm[:vm][:network_dns] || network_gateway
      puts "Network config for #{name} : #{ip_config[:ip]} / #{network_netmask}, gateway #{network_gateway}, bridge #{network_bridge}, dns #{network_dns}"

      puts "Cloning disk from #{vol_source} to #{name}.qcow2"
      @ssh.exec "virsh vol-clone #{vol_source} #{name}.qcow2 --pool #{pool}"

      root_disk = @ssh.capture "virsh vol-dumpxml #{name}.qcow2 --pool #{pool} | grep path"
      root_disk = root_disk.match(/<path>(.*)<\/path>/)[1]
      puts "New disk path #{root_disk}"

      disks = <<-EOF
<disk type='file' device='disk'>
  <driver name='qemu' type='qcow2'/>
  <source file='#{root_disk}'/>
  <target dev='vda' bus='virtio'/>
</disk>
EOF

      if vm[:vm][:disks]
        vm[:vm][:disks].each_with_index do |size, index|
          device = "vd#{('b'.ord + index).chr}"
          n = "#{name}_#{device}.qcow2"
          puts "Creating disk #{n} : #{size}"
          @ssh.exec "virsh vol-create-as default --format qcow2 --capacity #{size} --name #{n}"
          d = @ssh.capture "virsh vol-dumpxml #{n} --pool #{pool} | grep path"
          d = d.match(/<path>(.*)<\/path>/)[1]
          disks += <<-EOF
<disk type='file' device='disk'>
  <driver name='qemu' type='qcow2'/>
  <source file='#{d}'/>
  <target dev='#{device}' bus='virtio'/>
</disk>
EOF
        end
      end

      if vm[:vm][:block_devices]
        vm[:vm][:block_devices].each do |name, v|
          puts "Adding #{name} : #{v[:dev]}"
          disks += <<-EOF
<disk type='block' device='disk'>
  <driver name='qemu' type='raw'/>
  <source dev='#{v[:dev]}'/>
  <target dev='#{name}' bus='virtio'/>
</disk>
EOF
          if v[:fstype] && v[:format_fs]
            puts "Formating #{v[:dev]} to #{v[:fstype]}"
            @ssh.exec "mkfs -t #{v[:fstype]} #{v[:dev]}"
          end
        end
      end

      iface = <<-EOF
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet static
  address #{ip_config[:ip]}
  netmask #{network_netmask}
EOF

      iface += "  gateway #{network_gateway}" if network_gateway

      memory = vm[:vm][:memory] || 1024
      cpu = vm[:vm][:cpu] || 1

xml = <<-EOF
<domain type='kvm'>
  <name>#{name}</name>
  <memory unit='MiB'>#{memory}</memory>
  <vcpu>#{cpu}</vcpu>
  <os>
    <type arch='x86_64' machine='#{machine_type}'>hvm</type>
    <boot dev='hd'/>
  </os>
  <features>
    <acpi/>
    <apic/>
    <pae/>
  </features>
  <cpu mode='custom' match='exact'>
    <model fallback='allow'>SandyBridge</model>
    <vendor>Intel</vendor>
  </cpu>
  <clock offset='utc'/>
  <on_poweroff>destroy</on_poweroff>
  <on_reboot>restart</on_reboot>
  <on_crash>restart</on_crash>
  <devices>
    <emulator>/usr/bin/kvm</emulator>
    #{disks}
    <controller type='ide' index='0'/>
    <controller type='usb' index='0'/>
    <interface type='bridge'>
      <source bridge='#{network_bridge}'/>
      <model type='virtio'/>
    </interface>
    <serial type='pty'>
      <target port='0'/>
    </serial>
    <console type='pty'>
      <target type='serial' port='0'/>
    </console>
    <input type='mouse' bus='ps2'/>
    <graphics type='vnc' port='-1' autoport='yes'/>
    <video>
      <model type='cirrus' vram='9216' heads='1'/>
    </video>
    <memballoon model='virtio'>
    </memballoon>
  </devices>
EOF

      if hugespages
        xml += <<-EOF
<memoryBacking>
  <hugepages/>
</memoryBacking>
EOF
      end

      xml += <<-EOF
</domain>
EOF

      tmp_dir = "/tmp/" + (0...8).map { (65 + rand(26)).chr }.join
      @ssh.exec "mkdir -p #{tmp_dir}"
      @ssh.exec "modprobe nbd"
      @ssh.exec "umount /dev/nbd0p1 > /dev/null 2>&1 || true"
      @ssh.exec "qemu-nbd --disconnect /dev/nbd0 > /dev/null 2>&1 || true"
      @ssh.exec "qemu-nbd --connect=/dev/nbd0 #{root_disk}"
      @ssh.exec "mount /dev/nbd0p1 #{tmp_dir}"
      @ssh.exec "sh -c 'rm -f #{tmp_dir}/etc/ssh/ssh_host*key*'"
      @ssh.exec "ssh-keygen -t rsa -f #{tmp_dir}/etc/ssh/ssh_host_rsa_key -C root@#{name} -N '' -q "
      @ssh.exec "ssh-keygen -t dsa -f #{tmp_dir}/etc/ssh/ssh_host_dsa_key -C root@#{name} -N '' -q "
      @ssh.exec "ssh-keygen -t ecdsa -f #{tmp_dir}/etc/ssh/ssh_host_ecdsa_key -C root@#{name} -N '' -q"

      @ssh.exec "echo #{name} | sudo tee #{tmp_dir}/etc/hostname"

      @ssh.scp "#{tmp_dir}/etc/network/interfaces", iface
      @ssh.exec "rm #{tmp_dir}/etc/resolv.conf"
      if network_dns
        @ssh.exec "echo nameserver #{network_dns} | sudo tee #{tmp_dir}/etc/resolv.conf"
      else
        @ssh.exec "echo '' | sudo tee #{tmp_dir}/etc/resolv.conf"
      end

      @ssh.exec "cat #{tmp_dir}/etc/passwd | grep ^#{user} || sudo chroot #{tmp_dir} useradd #{user} --shell /bin/bash --create-home --home /home/#{user}"
      @ssh.exec "chroot #{tmp_dir} mkdir -p /home/#{user}/.ssh"
      @ssh.exec "chroot #{tmp_dir} chown -R #{user} /home/#{user}/.ssh"
      @ssh.scp "#{tmp_dir}/home/#{user}/.ssh/authorized_keys", ssh_keys.join("\n")
      @ssh.exec "chroot #{tmp_dir} which sudo || sudo chroot #{tmp_dir} apt-get install sudo -y"
      @ssh.exec "cat #{tmp_dir}/etc/sudoers | grep \"^#{user}\" || echo '#{user}   ALL=(ALL) NOPASSWD:ALL' | sudo tee -a #{tmp_dir}/etc/sudoers"

      @ssh.exec "chroot #{tmp_dir} which curl || sudo chroot #{tmp_dir} apt-get install curl -y"

      @ssh.exec "umount #{tmp_dir}"
      @ssh.exec "qemu-nbd --disconnect /dev/nbd0"

      @ssh.scp "/tmp/virsh_#{name}.xml", xml
      @ssh.exec "virsh define /tmp/virsh_#{name}.xml"
      @ssh.exec "rm -rf #{tmp_dir} /tmp/virsh_#{name}.xml"

      puts "Starting vm #{name}"
      @ssh.exec "virsh autostart #{name}"
      @ssh.exec "virsh start #{name}"

      wait_ssh ip_config[:ip], user
    end
  end

  def delete_vms l, no_dry
    return unless no_dry
    l.each do |name, vm|
      pool = vm[:vm][:pool] || "default"
      puts "Deleting #{name}"
      disks = @ssh.capture "virsh dumpxml #{name} | grep source | grep file"
      disks = disks.split("\n").map{|x| File.basename(x.match(/file=.(.*\.qcow2)/)[1])}
      @ssh.exec "virsh destroy #{name} || true"
      @ssh.exec "virsh undefine #{name}"
      disks.each do |x|
        @ssh.exec "virsh vol-delete #{x} --pool #{pool}"
      end
    end
  end

end