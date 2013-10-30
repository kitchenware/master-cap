
require 'master-cap/dns/base_dns'
require 'master-cap/helpers/ssh_helper'

class DnsDnsmasqShell < BaseDns

  include SshHelper

  def initialize cap, params
    @cap = cap
    @params = params
    [:user, :host, :sudo, :hosts_path].each do |x|
      raise "Missing params :#{x}" unless @params.key? x
    end
    @ssh = SshDriver.new @params[:host], @params[:user], @params[:sudo]
  end

  def file name
    "#{@params[:hosts_path]}/#{name}"
  end

  def read_current_records name
    content = @ssh.capture "cat #{file(name)} || true"
    result = []
    content.split(/\n/).each do |line|
      splitted = line.split(/ /)
      ip = splitted.shift
      splitted.each do |x|
        result << {:full_name => x, :ip => ip}
      end
    end
    result
  end

  def add_record name, record
    r = {:full_name => full_name, :ip => record[:ip]}
    @data << r
  end

  def delete_record name, full_name, record
    @data.reject!{|x| x[:full_name] == full_name}
  end

  def reload name
    ips = @data.map{|x| x[:ip]}.uniq
    lines = []
    ips.sort.each do |ip|
      lines << "#{ip} #{@data.select{|x| x[:ip] == ip}.map{|x| x[:full_name]}.join(' ')}"
    end
    @ssh.scp file(name), lines.join("\n")
    @ssh.exec "killall -HUP dnsmasq"
    puts "Dnsmasq updated on #{@params[:host]} for zone #{name}"
  end

end