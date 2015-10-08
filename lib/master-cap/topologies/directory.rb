
require 'yaml'
require 'erubis'
require 'deep_merge'

NODES_LIST={}
ROLES_MAP={}

Capistrano::Configuration.instance.load do

  topology_directory = fetch(:topology_directory, 'topology')

  set :env_list, Dir["#{topology_directory}/*.yml"]

  set :lazy_load_pattern, ["-%s$", "^%s$"]

  task :load_topology_directory do
    env_to_load = []
    linked_topologies = []
    if exists? :no_lazy_load
      env_to_load = env_list
    else
      env_to_load = []
      env_list.each do |env|
        top.logger.instance_variable_get("@options")[:actions].each do |a|
          lazy_load_pattern.each do |x|
            env_to_load << env if Regexp.new(x.gsub(/%s/, File.basename(env).split('.')[0])).match(a)
          end
        end
      end
      env_to_load.uniq!
    end
    while ! env_to_load.empty?
      f = env_to_load.shift
      next if f =~ /.inc.yml/
      env = File.basename(f).split('.')[0]
      puts "Loading file #{f}"
      TOPOLOGY[env] = YAML.load(File.read(f))

      load_included_files env, topology_directory
      if TOPOLOGY[env][:linked_topologies]
        TOPOLOGY[env][:linked_topologies].keys.each do |e|
          next if TOPOLOGY[e] || env_to_load.include?(e)
          env_to_load << "#{topology_directory}/#{e}.yml"
          linked_topologies << e.to_s
        end
      end

      translation_strategy_class = TOPOLOGY[env][:translation_strategy_class] || 'DefaultTranslationStrategy'
      TOPOLOGY[env][:translation_strategy] = Object.const_get(translation_strategy_class).new(env, TOPOLOGY[env])

      NODES_LIST[env] = []
      ROLES_MAP[env] = Hash.new { |hash, key| hash[key] = [] }

      class SimpleTopologyReader

        def initialize cap, env, topology
          @topology = topology
        end

        def read
          @topology[:topology]
        end

      end

      topology_reader_class = TOPOLOGY[env][:topology_reader_class] || 'SimpleTopologyReader'
      TOPOLOGY[env][:topology] = Object.const_get(topology_reader_class).new(self, env, TOPOLOGY[env]).read
      TOPOLOGY[env][:topology].each do |k, v|
        v[:topology_name] = k
        v[:capistrano_name] = get_translation_strategy(env).capistrano_name(k)
        v[:topology_hostname] = get_translation_strategy(env).hostname(k)
        v[:vm_name] = get_translation_strategy(env).vm_name(k)
        v[:host_ips] = {}
        get_translation_strategy(env).ip_types.each do |x|
          v[:host_ips][x] = get_translation_strategy(env).ip(x, k)
        end
        v[:admin_hostname] = v[:host_ips][:admin][:hostname]
        next unless v[:admin_hostname]
        node_roles = []
        node_roles += v[:roles].map{|x| x.to_sym} if v[:roles]
        node_roles << v[:type].to_sym if v[:type]
        n = {:name => k.to_s, :host => v[:admin_hostname], :roles => node_roles, :capistrano_name => v[:capistrano_name]}
        NODES_LIST[env] << n

        unless linked_topologies.include? env

          task v[:capistrano_name] do
            task_name = current_task.name.to_s
            NODES_LIST.each do |k, v|
              v.each do |n|
                if n[:capistrano_name] == task_name
                  server n[:host], *(n[:roles]) if n[:host]
                  load_cap_override k
                  break
                end
              end
            end
          end

          node_roles.each do |r|
            ROLES_MAP[env][r.to_s] << n
          end

        end

      end

      unless linked_topologies.include? env

        ROLES_MAP[env].each do |r, v|
          task "role-#{r}-#{env}" do
            task_name = current_task.name.to_s.match(/role-(.*)-(.*)/)
            local_role, local_env = $1, $2
            ROLES_MAP[local_env][local_role].each do |k|
              server k[:host], *(k[:roles]) if k[:host]
              load_cap_override local_env
            end
          end
        end

        task env do
          task_name = current_task.name.to_s
          NODES_LIST[task_name].each do |k|
            server k[:host], *(k[:roles]) if k[:host]
            load_cap_override task_name
          end
        end

      end

    end

    TOPOLOGY.keys.each do |env|
      if TOPOLOGY[env][:linked_topologies]
        TOPOLOGY[env][:linked_topologies].keys.each do |e|
          TOPOLOGY[env][:linked_topologies][e] = TOPOLOGY[e.to_s][:topology]
        end
      end
    end

    linked_topologies.each do |e|
      TOPOLOGY.delete e.to_s
      NODES_LIST.delete e.to_s
      ROLES_MAP.delete e.to_s
    end

  end

  def load_cap_override env
    TOPOLOGY[env][:cap_override].each do |k, v|
      set k, v
    end if TOPOLOGY[env][:cap_override]
  end

  def load_included_files env, topology_directory
    return unless TOPOLOGY[env][:includes]
    TOPOLOGY[env][:includes][:files].each do |f|
      template = nil
      begin
        file = "#{topology_directory}/#{f}"
        puts "Loading file #{file}"
        params = TOPOLOGY[env][:includes][:params] || {}
        template = YAML.load(::Erubis::Eruby.new(File.read(file)).result(params))
      rescue Exception => e
        puts "ERROR : Error while reading [#{file}]"
        error e
      end
      TOPOLOGY[env].deep_merge!(template, :merge_hash_arrays => true)
    end
    TOPOLOGY[env].delete :includes
  end

  on :load, :load_topology_directory

end
