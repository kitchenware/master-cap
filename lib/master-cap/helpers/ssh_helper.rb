
require_relative 'shell_helper'

class SshDriver

  include ShellHelper

  def initialize target, user, sudo
    @target = target
    @user = user
    @sudo = sudo
    @prefix = sudo ? " sudo " : ""
  end

  def scp filename, data, mode = '644'
    f = Tempfile.new(File.basename(filename))
    f.write(data)
    f.close
    if @sudo
      exec_local "scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=error #{f.path} #{@user}@#{@target}:/tmp/__tmp__"
      exec "sudo cp /tmp/__tmp__ #{filename}"
    else
      exec_local "scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=error #{f.path} #{@user}@#{@target}:#{filename}"
    end
    exec "sudo chmod #{mode} #{filename}" if mode
  end

  def exec cmd
    exec_local "ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=error #{@user}@#{@target} \"#{@prefix} #{cmd}\""
  end

  def capture cmd
    capture_local "ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=error #{@user}@#{@target} \"#{@prefix} #{cmd}\""
  end

end

module SshHelper

  def self.waituntil title, time
    ti=0
    puts "Wait until #{title}"
    until ti == time
      ti += 1
      sleep 1
      print "."
    end
    puts "."
  end

  def self.wait title, pool, timeout
    puts "Waiting for #{title}"
    start = Time.now.to_i
    stop = start + timeout
    while Time.now.to_i < stop
      begin
        if yield
          puts " ok !, duration #{Time.now.to_i - start}"
          return
        end
      rescue
      end
      $stdout.write "."
      $stdout.flush
      sleep pool
    end
    raise "Timeout while waiting end of #{title}"
  end

  def self.wait_ssh target, user, timeout = 60
    wait "SSH availability for #{target}", 2, timeout do
      begin
        exec_local "ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=error #{user}@#{target} -o ConnectTimeout=5 \"uname\""
        true
      rescue
        false
      end
    end
  end

end