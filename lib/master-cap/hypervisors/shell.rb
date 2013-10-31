
require 'master-cap/hypervisors/base'

class HypervisorShell < Hypervisor

  def initialize(cap, params)
    super(cap, params)
    @params = params
    [:list_vms, :create_vm, :delete_vm, :directory].each do |x|
      raise "Missing params :#{x}" unless @params.key? x
    end
  end

  def read_list
    result = ""
    @params[:list_vms].each do |x|
      result += execute_ruby_command(replace(x), true)
    end
    result.split("\n")
  end

  def replace cmd, others = {}
    @params.each do |k, v|
      cmd = cmd.gsub(/%#{k}%/, v) if v.is_a? String
    end
    others.each do |k, v|
      cmd = cmd.gsub(/%#{k}%/, v)
    end
    cmd
  end

  def create_vms vms, no_dry
    return unless no_dry
    vms.each do |name, vm|
      puts "Creating vm #{name}"
      ip = vm[:host_ips][:admin][:ip]
      @params[:create_vm].each do |x|
        execute_ruby_command(replace(x, :vm_ip => ip, :vm_name => name))
      end
    end
  end

  def delete_vms vms, no_dry
    return unless no_dry
    vms.each do |name, vm|
      puts "Deleting vm #{name}"
      ip = vm[:host_ips][:admin][:ip]
      @params[:delete_vm].each do |x|
        execute_ruby_command(replace(x, :vm_ip => ip, :vm_name => name))
      end
    end
  end

  def execute_ruby_command cmd, capture = false
    original_env = {}
    ENV.each do |k, v|
      original_env[k] = v
    end
    [
      'rvm_bin_path',
      'rvm_path',
      'rvm_prefix',
      'rvm_ruby_string',
      'rvm_version',
      'IRBRC',
      'MY_RUBY_HOME',
      'BUNDLE_GEMFILE',
      'BUNDLE_BIN_PATH',
      'RBENV_DIR',
      'RBENV_HOOK_PATH',
      'RBENV_ROOT',
      'RUBYOPT',
      'GEM_PATH',
      'GEM_HOME',
      'LD_LIBRARY_PATH',
      'RUBYLIB',
      'RUBY_VERSION',
    ].each do|x|
      ENV.delete x
    end
    if @params[:env]
      @params[:env].each do |k, v|
        ENV[k] = v
      end
    end
    ENV['PATH'] = ENV['PATH'].split(':').reject{|x| x.include?('.rvm')}.reject{|x| x.include?('rbenv') && x.include?('version')}.join(':')
    shell = "#{ENV['HOME']}/.rvm/bin/rvm-shell"
    shell = "#{ENV['HOME']}/.warp/common/ruby/warp-rbenv-shell" unless File.exists? shell
    shell = "#{ENV['SHELL']}" unless File.exists? shell
    puts "Running #{cmd}"
    cmd = "cd #{@params[:directory]} && #{cmd}"
    if capture
      result = %x{#{shell} -c \"#{cmd}\"}
    else
      Kernel.system "#{shell} -c \"#{cmd}\""
    end
    raise "Command #{cmd} return error code #{$?}" unless $? == 0
    original_env.each do |k, v|
      ENV[k] = v
    end
    capture ? result : ""
  end

end