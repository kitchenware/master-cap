
default[:master_cap_kvm][:ksm] = true

default[:master_cap_kvm][:hugepages] = "auto"
default[:master_cap_kvm][:hugepages_ratio] = 0.75

default[:master_cap_kvm][:tank] = "/tank"

default[:master_cap_kvm][:allow_chef_to_use_virsh] = true

default[:master_cap_kvm][:parallel_shutdown] = 10
