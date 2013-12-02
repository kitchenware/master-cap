
require_relative 'helpers/topological_sort'

APPS={}

Capistrano::Configuration.instance.load do

  set :apps_cap_directory, fetch(:apps_cap_directory, "deployment")

  namespace :apps do

    task :load_apps do
      apps_list = {}
      extented_tasks = {}
      TOPOLOGY.each do |name, env|
        if env[:apps]
          env[:apps].each do |n, a|
            apps_list[n] = [] unless apps_list[n]
            extented_tasks[n] = [] unless extented_tasks[n]
            apps_list[n] << name
            APPS["#{name}_#{n}"] = {:config => a, :env => name, :name => n}
            if a[:cap_wrapped_tasks]
              a[:cap_wrapped_tasks].each do |x|
                extented_tasks[n] << x unless extented_tasks[n].include? x
              end
            end
          end
        end
      end
      apps_list.keys.each do |x|

        namespace x do

          task :deploy do
            env = check_only_one_env
            get_app(env, x).deploy
          end

          extented_tasks[x].each do |y|
            task y do
              env = check_only_one_env
              get_app(env, x).wrapped_task(y)
            end
          end

        end
      end
    end

    task :deploy_all do
      env = check_only_one_env
      topological_sort(APPS).each do |x|
        top.apps.send(APPS[x][:name]).deploy if APPS[x][:env] == env
      end
    end

    def get_app env, name
      unless APPS["#{env}_#{name}"][:apps]
        clazz = "Apps#{APPS["#{env}_#{name}"][:config][:type].to_s.capitalize}"
        begin
          Object.const_get clazz
        rescue
          require "master-cap/apps/#{APPS["#{env}_#{name}"][:config][:type]}.rb"
        end
        APPS["#{env}_#{name}"][:apps] = Object.const_get(clazz).new(self, name, APPS["#{env}_#{name}"][:config])
      end
      APPS["#{env}_#{name}"][:apps]
    end

  end

  on :load, "apps:load_apps"

end
