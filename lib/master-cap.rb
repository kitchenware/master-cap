
unless Capistrano::Configuration.respond_to?(:instance)
  abort "master-cap requires Capistrano 2"
end

class String
   def underscore
     self.gsub(/(.)([A-Z])/,'\1_\2').downcase
   end
end

require 'master-cap/capistrano_helpers.rb'
require 'master-cap/git_repos_manager.rb'
require 'master-cap/translation_strategy.rb'
require 'master-cap/topology.rb'
require 'master-cap/tasks.rb'
