
class AppsBase

  attr_reader :cap
  attr_reader :name
  attr_reader :config

  def initialize cap, name, config
    @cap = cap
    @name = name
    @config = config
    [:finder, :cap_directory].each do |x|
      @cap.error "Please specify :#{x} attr for app #{name}" unless config[x]
    end
    config[:no_release_roles] ||= []
    config[:no_release_roles_exceptions] ||= [:app]
  end

  def get_topology(map)
    list = Hash.new { |hash, key| hash[key] = {}; hash[key][:roles] = []; }
    map.each do |role, mapped_roles|
      cap.find_servers(:roles => role).each do |n|
        no_release = false
        no_release_exceptions = false
        mapped_roles.each do |r|
          unless list[n].include? r
            list[n][:roles] << r
            no_release = true if config[:no_release_roles].include?(r)
            no_release_exceptions = true if config[:no_release_roles_exceptions].include?(r)
          end
        end
        list[n][:no_release] = true if no_release
        list[n][:no_release_exception] = true if no_release_exceptions
      end
    end
    list.each do |k, v|
      if v[:no_release_exception]
        v.delete :no_release
        v.delete :no_release_exception
      end
    end
    list
  end

  def default_opts
    {}
  end

  def wrapped_task task
    run_sub_cap task
  end

  def run_sub_cap cap_command, opts = {}
    f = Tempfile.new File.basename("sub_cap")
    f.write JSON.dump(get_topology(config[:finder]))
    f.close
    files_to_load = config[:cap_files_to_load] || []
    params = opts.merge(default_opts).map{|k, v| "-s #{k}=#{v}"}.join(" ")
    params += "-S http_proxy='#{cap.fetch(:http_proxy)}'" if cap.exists? :http_proxy
    params += "-S no_proxy='#{cap.fetch(:no_proxy)}'" if cap.exists? :no_proxy
    cmd = "cd #{cap.fetch(:apps_cap_directory)}/#{config[:cap_directory]} && TOPOLOGY=#{f.path} LOAD_INTO_CAP=#{files_to_load.join(':')} cap #{params} #{cap_command}"
    cap.exec_local cmd
  end

end