
require_relative 'base'

class AppsCustom < AppsBase

  def initialize cap, name, config
    super(cap, name, config)
    [:required_params].each do |x|
      raise "Please specify :#{x} attr" unless config.key? x
    end
  end

  def default_opts
    map = {
      :application => name,
      :user => config[:user] || "deploy",
    }
    map[:repository] = config[:repository] if config[:repository]
    map[:deploy_to] = config[:app_directory] if config[:app_directory]
    config[:required_params].each do |x|
      begin
        map[x] = @cap.fetch x
      rescue
        raise "Please specify param #{x}"
      end
    end
    map
  end

  def deploy
    run_sub_cap :deploy
  end

end