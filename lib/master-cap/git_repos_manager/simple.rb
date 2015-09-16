
class SimpleGitReposManager

  def initialize cap
    @cap = cap
  end

  def compute_override env
    result = {}
    repos.each do |x|
      result[x[:url]] = x[:ref] if x[:ref]
      if x[:url].match('master-cap.git')
        m = File.read('Gemfile.lock').match(/remote:[^\n]+master-cap.git\n\s*revision: ([0-9a-f]+)\n/)
        result[x[:url]] = m[1] if m
      end
    end
    result.size == 0 ? nil : result
  end

  def list
    repos.map{|x| x[:url]}
  end

  def compute_local_path
    repos.map{|x| x[:local_path] ? File.expand_path(x[:local_path]) : ""}.join(' ')
  end

  private

  def repos
    @cap.fetch(:git_repos, [])
  end
end
