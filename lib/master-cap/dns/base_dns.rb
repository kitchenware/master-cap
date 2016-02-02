
class BaseDns

  def process_list list
    compute_zone(list.uniq{|x| "#{x[:ip]}_#{x[:dns]}"}.map{|x| {:ip => x[:ip], :name => x[:dns]}})
  end

  def compute_zone list
    list.map do |x|
      raise "Unable to parse #{l[dns]}" unless x[:name].match(/^([^\.]+)\.(.*)$/)
      x[:hostname], x[:zone] = $1, $2
      x
    end
  end

  def by_zone list
    zones = {}
    list.each do |x|
      zones[x[:zone]] = [] unless zones[x[:zone]]
      zones[x[:zone]] << x
    end
    zones
  end

  def get_zone_name zone_name
    zone_name
  end

  def run list, no_dry
    list = process_list(list)
    by_zone(list).each do |zone, l|
      real_zone_name = get_zone_name(zone)
      current = read_current_records real_zone_name
      modified = yield real_zone_name, current, l
      reload zone if modified && no_dry
      puts "Zone #{zone} updated"
    end
  end

  def ensure_exists list, no_dry
    run list, no_dry do |real_zone_name, current, l|
      modified = false
      l.each do |x|
        unless current.find{|xx| xx[:ip] == x[:ip] && xx[:name] == x[:name]}
          puts "Adding record in zone #{real_zone_name} : #{x[:name]} : #{x[:ip]}"
          add_record real_zone_name, x if no_dry
          modified = true
        end
      end
      modified
    end
  end

  def ensure_not_exists list, no_dry
    run list, no_dry do |real_zone_name, current, l|
      modified = false
      l.each do |x|
        if current.find{|xx| xx[:ip] == x[:ip] && xx[:name] == x[:name]}
          puts "Removing record in zone #{real_zone_name} : #{x[:name]} : #{x[:ip]}"
          del_record real_zone_name, x if no_dry
          modified = true
        end
      end
      modified
    end
  end

  def check list, no_dry
    run list, no_dry do |real_zone_name, current, l|
      check_zone real_zone_name, l, no_dry
      true
    end
  end

end