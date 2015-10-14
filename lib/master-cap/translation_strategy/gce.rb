
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
    [:admin, :user, :private]
  end

  def ip type, name
    node = @topology[:topology][name]
    result = case type
      when :private
        { :ip => node[:private_ip], :hostname => node[:private_dns]}
      when :user
        { :ip => node[:public_hostname], :hostname => node[:public_hostname]}
      else
        { :ip => node[:public_hostname], :hostname => node[:public_hostname]}
    end
    #result = {:ip => (type == :private ? node[:private_ip] || node[:ip] : node[:ip]) || node[:hostname], :hostname => node[:private_dns] || node[:ip]} if node[:public_hostname] || node[:ip] 
    return result
    raise "No ip #{type} for node #{name}"
  end

  def vm_name name
    capistrano_name name
  end

end