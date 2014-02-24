
require_relative 'base'

class AppsCustom < AppsBase

  def initialize cap, name, config
    super(cap, name, config)
  end

  def default_opts
    map = {
      :application => name,
      :user => config[:user] || "deploy",
    }
    map[:repository] = config[:repository] if config[:repository]
    map[:deploy_to] = config[:app_directory] if config[:app_directory]
    (config[:required_params] || []).each do |x|
      begin
        map[x] = @cap.fetch x
      rescue
        @cap.error "Please specify param #{x} for app #{name}"
      end
    end
    (config[:default_params] || {}).each do |x, v|
      begin
        map[x] = @cap.fetch x
      rescue
        map[x] = v
      end
    end
    map
  end

  def deploy
    run_sub_cap :deploy
  end

end