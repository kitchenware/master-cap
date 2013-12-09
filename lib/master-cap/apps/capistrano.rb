
require_relative 'base'

class AppsCapistrano < AppsBase

  def initialize cap, name, config
    super(cap, name, config)
    [:scm].each do |x|
      @cap.error "Please specify :#{x} attr for app #{name}" unless config.key? x
    end
    @cap.error "Unknown scm #{config[:scm]} for app #{name}" if config[:scm] != :git
    config[:branch] ||= 'master'
  end

  def default_opts
    result = {
      :application => name,
      :repository => config[:repository],
      :scm => :git,
      :deploy_to => config[:app_directory],
      :user => config[:user] || "deploy",
    }
    result[:branch] = get_git_version config[:repository], @cap.fetch("branch_#{name}".to_sym, config[:branch])
    result
  end

  def deploy
    run_sub_cap :deploy
  end

  private

  def get_git_version git_repository, git_branch
    return git_branch if git_branch =~ /^[0-9a-f]{40}$/
    result = %x(git ls-remote #{git_repository} #{git_branch})
    error "No version found for branch #{git_branch} in git repository #{git_repository}" if result.empty?
    hash = result.split(/[\t\n]/)[0]
    puts "Git resolver : #{git_repository} / #{git_branch} => #{hash}"
    hash
  end

end