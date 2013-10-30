
require 'master-cap/apps/base'

class AppsCapistrano < AppsBase

  def initialize cap, name, config
    super(cap, name, config)
    [:scm].each do |x|
      raise "Please specify :#{x} attr" unless config.key? x
    end
    raise "Unknown scm #{config[:scm]}" if config[:scm] != :git
  end

  def default_opts
    {
      :application => name,
      :repository => config[:repository],
      :scm => :git,
      :deploy_to => config[:app_directory],
      :user => config[:user] || "deploy",
    }
  end

  def deploy
    run_sub_cap :deploy
  end

end