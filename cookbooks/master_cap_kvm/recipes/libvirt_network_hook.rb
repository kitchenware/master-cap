
incremental_template "/etc/libvirt/hooks/network" do
  mode '0755'
  header <<-EOF
#!/bin/bash

EOF
  owner "root"
end
