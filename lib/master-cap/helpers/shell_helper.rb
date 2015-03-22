
module ShellHelper

  def self.exec_local(cmd)
    raise "Command execution error : #{cmd}" unless system cmd
  end

  def self.capture_local cmd
    result = %x{#{cmd}}
    raise "Command execution error : #{cmd}" unless $? == 0
    result
  end

end
