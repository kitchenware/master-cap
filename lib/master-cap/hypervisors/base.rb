
require_relative '../helpers/shell_helper'

class Hypervisor

  include ShellHelper

  def initialize(cap, params)
    @cap = cap
    clear_caches
  end

  def clear_caches
    @l = nil
    @infos = {}
  end

  def list
    @l ||= read_list
  end

  def exist?(name)
    list.include? name
  end

  def vm_info(name)
    unless @infos[name]
      @infos[name] = read_info name
    end
    @infos[name]
  end

  def dns_ips(vms, allow_not_found)
    self.class.extract_dns_ips vms
  end

  def self.extract_dns_ips(vms)
    result = []
    vms.each do |name, config|
      config[:host_ips].except(:user, :admin).each do |k, v|
        result << {:vm_name => name.to_s, :net => k, :dns => v[:hostname], :ip => v[:ip]}
      end
    end
    result
  end
  def start_vms l, no_dry
    @cap.error "Not implemented start_vms in #{self.class}"
  end

  def stop_vms l, no_dry
    @cap.error "Not implemented stop_vms in #{self.class}"
  end

  def reboot_vms l, no_dry
    @cap.error "Not implemented reboot_vms in #{self.class}"
  end

  def info_vms l, no_dry
    @cap.error "Not implemented info_vms in #{self.class}"
  end

  def console_vms l, no_dry
    @cap.error "Not implemented console_vms in #{self.class}"
  end

end
