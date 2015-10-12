
require_relative 'base_dns'
require_relative '../helpers/ssh_helper'

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
        result << {:name => x, :ip => ip}
      end
    end
    result
  end

  def add_record name, record
    data = read_current_records name
    data << {:name => record[:name], :ip => record[:ip]}
    save name, data
  end

  def del_record name, record
    data = read_current_records name
    data.reject!{|x| x[:name] == record[:name]}
    save name, data
  end

  def save name, data
    ips = data.map{|x| x[:ip]}.uniq
    lines = []
    ips.sort.each do |ip|
      lines << "#{ip} #{data.select{|x| x[:ip] == ip}.map{|x| x[:name]}.join(' ')}"
    end
    @ssh.scp file(name), lines.join("\n")
  end

  def reload name
    @ssh.exec "pkill -HUP dnsmasq"
    puts "Dnsmasq updated on #{@params[:host]} for zone #{name}"
  end

end