
class GceTranslationStrategy

  def initialize env, topology
    @env = env
    @topology = topology
  end

  def capistrano_name name
    return name.to_s if @topology[:no_node_suffix] || name.include?(@env)
    "#{name}-#{@env}"
  end

  def hostname name
    return name.to_s if @topology[:no_node_suffix]
    "#{name}-#{@env}"
  end

  def ip_types
    [:admin, :user, :nat]
  end

  def ip type, name
    node = @topology[:topology][name]
    return {:hostname => node[:public_hostname]} if (type == :admin || type == :nat) && node[:public_hostname]
    return {:ip => node[:private_ip]} if type == :user && node[:private_ip]
    return {:ip => node[:public_hostname]} if type == :user && !node[:private_ip]
    raise "No ip #{type} for node #{name}"
  end

  def vm_name name
    capistrano_name name
  end

end