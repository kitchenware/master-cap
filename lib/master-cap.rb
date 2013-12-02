
unless Capistrano::Configuration.respond_to?(:instance)
  abort "master-cap requires Capistrano 2"
end

class String
   def underscore
     self.gsub(/(.)([A-Z])/,'\1_\2').downcase
   end
end

require_relative 'master-cap/capistrano_helpers'
require_relative 'master-cap/git_repos_manager'
require_relative 'master-cap/translation_strategy'
require_relative 'master-cap/topology'
require_relative 'master-cap/tasks'
