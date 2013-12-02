
# http://en.wikipedia.org/wiki/Topological_sorting#Algorithms
def topological_sort map
  map = map.dup
  # L ← Empty list that will contain the sorted elements
  l = []
  # S ← Set of all nodes with no incoming edges
  s = map.keys.sort_by{|x| x.to_s}.reject do |x|
    # translate app_name
    x = map[x][:name].to_sym
    incoming_edge = false
    map.each do |k, v|
      incoming_edge = true if v[:config][:depends] && v[:config][:depends].include?(x)
    end
    incoming_edge
  end
  # while S is non-empty do
  while !s.empty? do
    # remove a node n from S
    n = s.pop
    # insert n into L
    l.push n
    # for each node m with an edge e from n to m do
    (map[n][:config][:depends] || []).dup.each do |m|
      # remove edge e from the graph
      map[n][:config][:depends].delete m
      # translate app_name
      m = map.find{|k, v| v[:name] == m.to_sym}[0]
      # if m has no other incoming edges then
      m_incoming_edge = 0
      map.each do |k, v|
        m_incoming_edge += 1 if v[:config][:depends] && v[:config][:depends].include?(m)
      end
      # insert m into S
      s.push m if m_incoming_edge == 0
    end
  end
  # if graph has edges then
  #   return error (graph has at least one cycle)
  map.each do |k, v|
    raise "Cycle detected" if v[:config][:depends] && v[:config][:depends].size > 0
  end
  # else
  #  return L (a topologically sorted order)
  l.reverse
end
