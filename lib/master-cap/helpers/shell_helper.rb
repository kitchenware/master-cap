
module ShellHelper

  def exec_local(cmd)
    raise "Command execution error : #{cmd}" unless system cmd
  end

  def capture_local cmd
    result = %x{#{cmd}}
    raise "Command execution error : #{cmd}" unless $? == 0
    result
  end

end
