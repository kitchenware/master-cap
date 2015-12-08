require 'tempfile'
require 'json'
require 'yaml'

Capistrano::Configuration.instance.load do

  namespace :chef do

    set :master_chef_path, fetch(:master_chef_path, '../master-chef')
    set :git_repos_manager, Object.const_get(fetch(:git_repos_manager_class, 'EmptyGitReposManager')).new(self)

    task :generate_local_json do
      env = check_only_one_env
      find_nodes(:roles => chef_role).each do |env, node, s|
        roles = []
        recipes = []
        if exists?(:autoload_runlist) && autoload_runlist
          roles << "master_cap_runlist_loader"
        else
          roles += TOPOLOGY[env][:default_role_list] if TOPOLOGY[env][:default_role_list] && !node[:no_default_role]
          roles += node[:roles] if node[:roles]
          recipes += node[:recipes] if node[:recipes]
        end
        git_repos = git_repos_manager.list
        git_repos += node[:git_repos] if node[:git_repos]
        json = JSON.pretty_generate({
          :repos => {
            :git => git_repos,
          },
          :run_list => roles.map{|x| "role[#{x}]"} + recipes.map{|x| "recipe[#{x}]"},
          :node_config => {
            :topology_node_name => node[:topology_name]
          },
        })
        puts json
        f = Tempfile.new File.basename("local_json_#{name}")
        f.write json
        f.close
        upload_to_root f.path, "/opt/master-chef/etc/local.json", {:hosts => [s]}
      end
      git_repos_manager.list.each do |git_repo|
        if git_repo =~ /^.+@.+:.+\.git$/
          run "sudo ssh -o StrictHostKeyChecking=no #{git_repo.split(':')[0]} echo toto > /dev/null 2>&1 || true ", :roles => chef_role
        end
      end
    end

    def get_prefix
      prefix = ""
      prefix += "http_proxy=#{http_proxy} https_proxy=#{http_proxy} " if exists? :http_proxy
      prefix += "DRY_RUN=1" if exists? :dry_run
      prefix
    end

    task :upload_git_tag_override, :roles => :linux_chef do
      env = check_only_one_env

      git_tag_override = git_repos_manager.compute_override(env)

      if git_tag_override
        f = Tempfile.new File.basename("git_tag_override")
        f.write JSON.dump(git_tag_override)
        f.close

        upload_to_root f.path, "/opt/master-chef/etc/local.json.git_tag_override"
      end

    end

    task :upload_topology, :roles => :linux_chef  do
      env = check_only_one_env

      f = Tempfile.new "topology_env"
      f.write JSON.dump(TOPOLOGY[env])
      f.close
      upload_to_root f.path, "/opt/master-chef/etc/topology.json"
    end

    task :upload_topology_local, :roles => :linux_chef  do
      env = check_only_one_env
      f = Tempfile.new "topology_env"
      f.write JSON.dump(TOPOLOGY[env])
      f.close
      exec_local "ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=error chef@127.0.0.1 'sudo cp #{f.path} /opt/master-chef/etc/topology.json'"
    end

    task :exec_local_chef, :roles => :linux_chef  do
      env = check_only_one_env
      exec_local "ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=error chef@127.0.0.1 '/opt/master-chef/bin/master-chef.sh'"
    end

    task :default, :roles => chef_role  do
      upload_topology
      upload_git_tag_override
      n = []
      find_nodes(:roles => chef_role).each do |env, node, s|
        n << node[:topology_name]
      end
      prefix = get_prefix + " PARALLEL_NODES=#{n.join(',')}"
      run "#{prefix} /opt/master-chef/bin/master-chef.sh"
    end

    task :stack, :roles => chef_role  do
      run "sudo cat /opt/chef/var/cache/chef-stacktrace.out"
    end

    task :show_last_attrs, :roles => chef_role  do
      find_nodes(:roles => chef_role).each do |env, node, s|
        f = "#{node[:capistrano_name]}.json"
        File.write(f, capture("sudo cat /opt/master-chef/var/last/last_attributes.json", :hosts => s))
        puts "Last attributes for #{node[:capistrano_name]} written to #{f}"
      end
    end

    task :purge_cache, :roles => chef_role do
      run "sudo rm -rf /opt/master-chef/var/git_repos"
    end

    task :local, :roles => chef_role  do
      upload_topology
      find_servers(:roles => chef_role).each do |x|
        prefix = ""
        prefix += get_prefix
        prefix += "PROXY_COMMAND='#{ssh_options[:proxy].command_line_template}' " if exists?(:ssh_options) && ssh_options[:proxy]
        command = "sh -c \"#{prefix} #{master_chef_path}/runtime/chef_local.rb #{x} #{git_repos_manager.compute_local_path}\""
        abort unless system command
      end
    end

    task :install, :roles => chef_role do
      env = check_only_one_env
      prefix = get_prefix
      prefix += "PROXY=#{http_proxy} " if exists? :http_proxy
      prefix += "MASTER_CHEF_HASH_CODE=#{master_chef_hash_code} " if exists? :master_chef_hash_code
      version = exists?(:master_chef_hash_code) ? master_chef_hash_code : "master"
      run "#{get_prefix} curl -f -s -L http://rawgithub.com/kitchenware/master-chef/#{version}/runtime/bootstrap.sh?#{version} | #{prefix} bash"
    end

  end

end