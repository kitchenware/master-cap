
require 'timeout'

Capistrano::Configuration.instance.load do

  def exec_local_with_timeout cmd, timeout
    pid = Process.fork { exec cmd }
    begin
      Timeout.timeout(timeout) do
        Process.wait(pid)
        error "Wrong return code for #{cmd} : #{$?.exitstatus}" unless $?.exitstatus == 0
      end
    rescue Timeout::Error
      Process.kill('TERM', pid)
      error "Timeout when executing #{cmd}"
    end
  end

  def exec_local cmd
    begin
      abort "#{cmd} failed. Aborting..." unless system cmd
    rescue
      abort "#{cmd} failed. Aborting..."
    end
  end

  def capture_local cmd
    begin
      result = %x{#{cmd}}
      abort "#{cmd} failed. Aborting..." unless $? == 0
      result
    rescue
      abort "#{cmd} failed. Aborting..."
    end
  end

  def upload_to_root local, remote, options = {}
    tmp_file = "/tmp/#{File.basename(remote)}"
    upload local, tmp_file, options
    run_root "mv #{tmp_file} #{remote}", options
  end

  def run_root cmd, options = {}
    run "sudo su - -c '#{cmd}'", options
  end

  def error msg
    abort "Error : #{msg}"
  end

  def fill s, k
    s.length >= k ? s : fill(s.to_s + " ", k)
  end

  def multiple_capture command, options = nil
    result = {}
    launch = true
    launch = false if options && options[:hosts] && options[:hosts] == []
    if launch
      begin
        parallel(options) do |session|
          session.else command do |channel, stream, data|
            env, name, node = find_node(channel.properties[:server].host)
            if block_given?
              result[name] = yield name, node, data
            else
              result[name] = data
            end
          end
        end
      rescue Capistrano::ConnectionError => e
        if options[:hide_errors]
          puts "\e[31m#{e}\e[0m"
        else
          raise e
        end
      end
    end
    if options
      default_value = options[:default_value]
      if default_value
        find_servers.map{|x| find_node x.host}.each do |env, name, node|
          result[name] = default_value unless result[name]
        end
      end
    end
    result
  end

  def error msg
    abort "Error : #{msg}"
  end

end