variable "nodes" {
  default = {
    storage-node = { ip = "192.168.56.50", memory = 3072, vcpu = 2, disk_gb = 10 }
    idp-node     = { ip = "192.168.56.20", memory = 4096, vcpu = 4, disk_gb = 20 }
    lb-node      = { ip = "192.168.56.10", memory = 1536, vcpu = 1, disk_gb = 10 }
    bastion-01   = { ip = "192.168.56.11", memory = 1536, vcpu = 1, disk_gb = 10 }
    bastion-02   = { ip = "192.168.56.12", memory = 1536, vcpu = 1, disk_gb = 10 }
    test-server  = { ip = "192.168.56.60", memory = 1536, vcpu = 1, disk_gb = 10 }
  }
}

variable "extra_disks" {
  description = "Additional data disks: RAID pair for storage, pgdata for PostgreSQL"
  default = {
    "storage-node-raid1" = { node = "storage-node", size_gb = 25 }
    "storage-node-raid2" = { node = "storage-node", size_gb = 25 }
    "test-server-pgdata" = { node = "test-server",  size_gb = 20 }
  }
}
