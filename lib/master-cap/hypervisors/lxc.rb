
require_relative 'base'
require_relative '../helpers/ssh_helper'

require 'digest/md5'

class HypervisorLxc < Hypervisor

  include SshHelper

  def initialize cap, params
    super(cap, params)
    @params = params
    [:lxc_user, :lxc_host, :lxc_sudo].each do |x|
      raise "Missing params :#{x}" unless @params.key? x
    end
    @ssh = SshDriver.new @params[:lxc_host], @params[:lxc_user], @params[:lxc_sudo]
  end

  def read_list
    @ssh.capture("lxc-ls").split("\n")
  end

  def start_vms l, no_dry
    return unless no_dry
    l.each do |name, vm|
      puts "Starting #{name}"
      @ssh.exec "lxc-start -d -n #{name}"
      wait_ssh vm[:hostname], @cap.fetch(:user)
    end
  end

  def stop_vms l, no_dry
    return unless no_dry
    l.each do |name, vm|
      puts "Stopping #{name}"
      @ssh.exec "lxc-stop -n #{name}"
    end
  end

  def default_vm_config
    @params[:default_vm]
  end

  def create_vms l, no_dry
    return unless no_dry
    l.each do |name, vm|
      fs_backing = vm[:vm][:fs_backing] || :chroot
      ip_config = vm[:host_ips][:internal] || vm[:host_ips][:admin]
      template_name = vm[:vm][:template_name]
      template_opts = vm[:vm][:template_opts] || ""
      raise "No template specified for vm #{name}" unless template_name
      puts "Creating #{name}, using template #{template_name}, options #{template_opts}"
      network_gateway = vm[:vm][:network_gateway] || @ssh.capture("/bin/sh -c '. /etc/default/lxc && echo \\$LXC_ADDR'").strip
      network_netmask = vm[:vm][:network_netmask] || @ssh.capture("/bin/sh -c '. /etc/default/lxc && echo \\$LXC_NETMASK'").strip
      network_bridge = vm[:vm][:network_bridge] || @ssh.capture("/bin/sh -c '. /etc/default/lxc && echo \\$LXC_BRIDGE'").strip
      network_dns = vm[:vm][:network_dns] || network_gateway
      puts "Network config for #{name} : #{ip_config[:ip]} / #{network_netmask}, gateway #{network_gateway}, bridge #{network_bridge}, dns #{network_dns}"

      ssh_keys = vm[:vm][:ssh_keys]

      if fs_backing == :lvm
        raise "No vg for #{name}" unless vm[:vm][:lvm][:vg_name]
        raise "No size for #{name}" unless vm[:vm][:lvm][:root_size]
      end

      user = @cap.fetch(:user)

      iface = <<-EOF
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet static
  address #{ip_config[:ip]}
  netmask #{network_netmask}
  gateway #{network_gateway}
EOF

      override_ohai = {}
      config = []

      config << "lxc.network.type = veth"
      config << "lxc.network.link = #{network_bridge}"
      config << "lxc.network.flags = up"
      config << ""
      if vm[:vm][:memory]
        config << "lxc.cgroup.memory.limit_in_bytes = #{vm[:vm][:memory]}"
        override_ohai[:memory] = {} unless override_ohai[:memory]
        override_ohai[:memory][:total] = vm[:vm][:memory]
      end
      if vm[:vm][:memory_swap]
        config << "lxc.cgroup.memory.memsw.limit_in_bytes = #{vm[:vm][:memory_swap]}"
      end
      if vm[:vm][:cpu_shares]
        config << "lxc.cgroup.cpu.shares = #{vm[:vm][:cpu_shares]}"
        override_ohai[:cpu] = {} unless override_ohai[:cpu]
        override_ohai[:cpu][:total] = (vm[:vm][:cpu_shares] / 1024).to_i
      end
      config << ""
      config << ""
      @ssh.scp "/tmp/lxc_config_#{name}", config.join("\n")
      if fs_backing == :lvm
        command = "lxc-create -t #{template_name} -n #{name} -f /tmp/lxc_config_#{name}"
        command += " -B lvm --vgname #{vm[:vm][:lvm][:vg_name]} --fssize #{vm[:vm][:lvm][:root_size]}" if fs_backing == :lvm
        command += " -- #{template_opts}"
        puts "Command line : #{command}"
        @ssh.exec command
      end
      if fs_backing == :btrfs
        template_prefix = vm[:vm][:template_prefix] || "/usr/share/lxc/templates/lxc-"
        res = Digest::MD5.hexdigest(@ssh.capture "cat #{template_prefix}#{template_name}")
        clone_image = "template-btrfs-#{template_name}-#{res}"
        a = @ssh.capture("lxc-ls | grep #{clone_image} || true")
        if a.empty?
          puts "Creating template #{clone_image}"
          command = "lxc-create -t #{template_name} -n #{clone_image} -B btrfs"
          puts "Command line : #{command}"
          @ssh.exec command
        end
        command = "lxc-clone -o #{clone_image} -n #{name} -s"
        puts "Command line : #{command}"
        @ssh.exec command
        @ssh.exec "cat /tmp/lxc_config_#{name} | sudo tee -a /var/lib/lxc/#{name}/config"
      end
      if fs_backing == :chroot
        command = "lxc-create -t #{template_name} -n #{name} -f /tmp/lxc_config_#{name} -- #{template_opts}"
        puts "Command line : #{command}"
        @ssh.exec command
      end
      @ssh.exec "mount /dev/#{vm[:vm][:lvm][:vg_name]}/#{name} /var/lib/lxc/#{name}/rootfs" if fs_backing == :lvm
      @ssh.exec "rm -f /var/lib/lxc/#{name}/rootfs/etc/ssh/ssh_host*key*"
      @ssh.exec "ssh-keygen -t rsa -f /var/lib/lxc/#{name}/rootfs/etc/ssh/ssh_host_rsa_key -C root@#{name} -N '' -q "
      @ssh.exec "ssh-keygen -t dsa -f /var/lib/lxc/#{name}/rootfs/etc/ssh/ssh_host_dsa_key -C root@#{name} -N '' -q "
      @ssh.exec "ssh-keygen -t ecdsa -f /var/lib/lxc/#{name}/rootfs/etc/ssh/ssh_host_ecdsa_key -C root@#{name} -N '' -q"

      @ssh.exec "sed -i 's/^127.0.1.1.*$/127.0.1.1 #{vm[:admin_hostname]} #{name}/' /var/lib/lxc/#{name}/rootfs/etc/hosts"

      @ssh.scp "/var/lib/lxc/#{name}/rootfs/etc/network/interfaces", iface
      @ssh.exec "rm /var/lib/lxc/#{name}/rootfs/etc/resolv.conf"
      @ssh.exec "echo nameserver #{network_dns} | sudo tee /var/lib/lxc/#{name}/rootfs/etc/resolv.conf"

      # @ssh.exec "chroot /var/lib/lxc/#{name}/rootfs userdel ubuntu"
      # @ssh.exec "chroot /var/lib/lxc/#{name}/rootfs rm -rf /home/ubuntu"

      @ssh.exec "cat /var/lib/lxc/#{name}/rootfs/etc/passwd | grep ^chef || sudo chroot /var/lib/lxc/#{name}/rootfs useradd #{user} --shell /bin/bash --create-home --home /home/#{user}"
      @ssh.exec "chroot /var/lib/lxc/#{name}/rootfs mkdir /home/#{user}/.ssh"
      @ssh.scp "/var/lib/lxc/#{name}/rootfs/home/#{user}/.ssh/authorized_keys", ssh_keys.join("\n")
      @ssh.exec "chroot /var/lib/lxc/#{name}/rootfs chown -R #{user} /home/#{user}/.ssh"
      @ssh.exec "cat /var/lib/lxc/#{name}/rootfs/etc/sudoers | grep \"^chef\" || echo 'chef   ALL=(ALL) NOPASSWD:ALL' | sudo tee -a /var/lib/lxc/#{name}/rootfs/etc/sudoers"

      @ssh.exec "chroot /var/lib/lxc/#{name}/rootfs which curl || sudo chroot /var/lib/lxc/#{name}/rootfs apt-get install curl -y"

      @ssh.scp "/var/lib/lxc/#{name}/rootfs/opt/master-chef/etc/override_ohai.json", JSON.dump(override_ohai) unless override_ohai.empty? || @params[:no_ohai_override]
      @ssh.exec "umount /dev/#{vm[:vm][:lvm][:vg_name]}/#{name}" if fs_backing == :lvm
      @ssh.exec "rm /tmp/lxc_config_#{name}"
      @ssh.exec "lxc-start -d -n #{name}"
      @ssh.exec "ln -s /var/lib/lxc/#{name}/config /etc/lxc/auto/#{name}.conf"
      wait_ssh vm[:host_ips][:admin][:ip], user
    end
  end

  def delete_vms l, no_dry
    return unless no_dry
    l.each do |name, vm|
      puts "Deleting #{name}"
      @ssh.exec "lxc-stop -n #{name} || true"
      @ssh.exec "lxc-destroy -n #{name}"
      @ssh.exec "rm -f /etc/lxc/auto/#{name}"
    end
  end

end