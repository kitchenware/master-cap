
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
      puts "Starting #{name} on #{@params[:hypervisor_id]}"
      @ssh.exec "virsh start #{name}"
      wait_ssh vm[:hostname], @cap.fetch(:user)
    end
  end

  def stop_vms l, no_dry
    return unless no_dry
    l.each do |name, vm|
      puts "Stopping #{name} on #{@params[:hypervisor_id]}"
      @ssh.exec "virsh destroy #{name}"
    end
  end

  def default_vm_config
    @params[:default_vm]
  end

  def create_vms l, no_dry
    return unless no_dry
    l.each do |name, vm|
      puts "Creating #{name} on #{@params[:hypervisor_id]}"
      user = @cap.fetch(:user)
      ssh_keys = vm[:vm][:ssh_keys] || []
      vol_source = vm[:vm][:vol_source]
      machine_type = vm[:vm][:machine_type] || "pc-1.3"
      pool = vm[:vm][:pool] || "default"
      hugespages = vm[:vm][:disable_hugepages] ? false : true
      ip_config = vm[:host_ips][:internal] || vm[:host_ips][:admin]
      network_gateway = vm[:vm][:network_gateway] || vm[:vm][:network_by_bridge][vm[:vm][:network_bridge]][:network_gateway]
      network_netmask = vm[:vm][:network_netmask] || vm[:vm][:network_by_bridge][vm[:vm][:network_netmask]][:network_netmask]
      network_bridge = vm[:vm][:network_bridge]
      network_dns = vm[:vm][:network_dns] || network_gateway
      puts "Network config for #{name} : #{ip_config[:ip]} / #{network_netmask}, gateway #{network_gateway}, bridge #{network_bridge}, dns #{network_dns}"

      @ssh.exec("virsh pool-refresh #{pool}")

      unless @ssh.capture("virsh vol-list --pool #{pool} | grep #{name}.qcow2 || true").empty?
        @ssh.exec "virsh vol-delete --pool #{pool} #{name}.qcow2"
      end

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
      disk_index = 0
      if vm[:vm][:disks]
        vm[:vm][:disks].each do |size|
          while true
            device = "vd#{('b'.ord + disk_index).chr}"
            break unless vm[:vm][:block_devices]
            break unless vm[:vm][:block_devices][device] || vm[:vm][:block_devices][device.to_sym]
            disk_index += 1
          end
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
        vm[:vm][:block_devices].each do |disk_name, v|
          if v[:dev]
          elsif v[:size] && v[:vg_source]
            n = "#{name}-#{disk_name}"
            if @ssh.capture("lvs | grep #{n} || true").empty?
              @ssh.exec "lvcreate -n #{n} -L #{v[:size]} #{v[:vg_source]}"
            end
            v[:dev] = "/dev/mapper/#{v[:vg_source]}-#{n.gsub('-', '--')}"
          else
            raise "Not enough options for block devices #{JSON.dump(v)}"
          end
          puts "Adding #{disk_name} : #{v[:dev]}"
          disks += <<-EOF
<disk type='block' device='disk'>
  <driver name='qemu' type='raw'/>
  <source dev='#{v[:dev]}'/>
  <target dev='#{disk_name}' bus='virtio'/>
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
      @ssh.exec "modprobe nbd max_part=8"
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
      network_dns.split(" ").each do |x|
        @ssh.exec "echo nameserver #{x} | sudo tee -a #{tmp_dir}/etc/resolv.conf > /dev/null"
      end

      @ssh.exec "cat #{tmp_dir}/etc/passwd | grep ^#{user} > /dev/null || sudo chroot #{tmp_dir} useradd #{user} --shell /bin/bash --create-home --home /home/#{user}"
      @ssh.exec "chroot #{tmp_dir} mkdir -p /home/#{user}/.ssh"
      @ssh.exec "chroot #{tmp_dir} chown -R #{user} /home/#{user}/.ssh"
      current_keys = @ssh.capture "cat #{tmp_dir}/home/#{user}/.ssh/authorized_keys || true"
      @ssh.scp "#{tmp_dir}/home/#{user}/.ssh/authorized_keys", (current_keys.split("\n") + ssh_keys).uniq.join("\n")
      @ssh.exec "chroot #{tmp_dir} which sudo > /dev/null || sudo chroot #{tmp_dir} apt-get install sudo -y"
      @ssh.exec "cat #{tmp_dir}/etc/sudoers | grep \"^#{user}\" > /dev/null || echo '#{user}   ALL=(ALL) NOPASSWD:ALL' | sudo tee -a #{tmp_dir}/etc/sudoers > /dev/null"

      @ssh.exec "chroot #{tmp_dir} which curl > /dev/null || sudo chroot #{tmp_dir} apt-get install curl -y"

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

  def update_vms l, no_dry
    l.each do |name, vm|
      pool = vm[:vm][:pool] || "default"
      puts "Updating #{name} on #{@params[:hypervisor_id]}"
      disks = @ssh.capture "virsh dumpxml #{name} | grep source | grep file"
      disks = disks.split("\n").map{|x| File.basename(x.match(/file=.(.*\.qcow2)/)[1])}
      if vm[:vm][:disks]
        disk_index = 0
        vm[:vm][:disks].each do |size|
          while true
            device = "vd#{('b'.ord + disk_index).chr}"
            break unless vm[:vm][:block_devices]
            break unless vm[:vm][:block_devices][device] || vm[:vm][:block_devices][device.to_sym]
            disk_index += 1
          end
          n = "#{name}_#{device}.qcow2"
          unless disks.include? n
            puts "Adding disk #{size} on #{name}"
            next unless no_dry

            @ssh.exec("virsh pool-refresh #{pool}")

            unless @ssh.capture("virsh vol-list --pool #{pool} | grep #{n} || true").empty?
              @ssh.exec "virsh vol-delete --pool #{pool} #{n}"
            end

            @ssh.exec "virsh vol-create-as default --format qcow2 --capacity #{size} --name #{n}"
            d = @ssh.capture "virsh vol-dumpxml #{n} --pool #{pool} | grep path"
            d = d.match(/<path>(.*)<\/path>/)[1]
            disk = <<-EOF
<disk type='file' device='disk'>
  <driver name='qemu' type='qcow2'/>
  <source file='#{d}'/>
  <target dev='#{device}' bus='virtio'/>
</disk>
EOF
            @ssh.scp "/tmp/virsh_disk.xml", disk
            @ssh.exec "virsh attach-device --persistent #{name} /tmp/virsh_disk.xml"
            @ssh.exec "rm /tmp/virsh_disk.xml"
          end
        end
      end
    end
  end

  def delete_vms l, no_dry
    return unless no_dry
    l.each do |name, vm|
      pool = vm[:vm][:pool] || "default"
      puts "Deleting #{name} on #{@params[:hypervisor_id]}"
      disks = @ssh.capture "virsh dumpxml #{name} | grep source | grep file"
      disks = disks.split("\n").map{|x| File.basename(x.match(/file=.(.*\.qcow2)/)[1])}
      lvs = @ssh.capture "virsh dumpxml #{name} | grep mapper || true"
      lvs = lvs.split("\n").map{|x| x.match(/dev='([^']+)'/)[1]}
      @ssh.exec "virsh destroy #{name} || true"
      @ssh.exec "virsh undefine #{name}"
      disks.each do |x|
        @ssh.exec "virsh vol-delete #{x} --pool #{pool}"
      end
      lvs.each do |x|
        @ssh.exec "lvremove --force #{x}"
      end
    end
  end

end