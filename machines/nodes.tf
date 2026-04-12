locals {
  # Map each node to its sorted list of extra disk keys
  node_extra_disks = {
    for node_key, node in var.nodes :
    node_key => sort([
      for disk_key, disk in var.extra_disks :
      disk_key if disk.node == node_key
    ])
  }

  dev_letters = ["b", "c", "d", "e", "f"]
}

# Base Fedora cloud image
resource "libvirt_volume" "fedora_base" {
  name = "fedora42-base.qcow2"
  pool = "default"

  target = {
    format = { type = "qcow2" }
  }

  create = {
    content = {
      url = "https://download.fedoraproject.org/pub/fedora/linux/releases/42/Cloud/x86_64/images/Fedora-Cloud-Base-Generic-42-1.1.x86_64.qcow2"
    }
  }
}

# Per-node copy-on-write boot disks
resource "libvirt_volume" "node_disk" {
  for_each = var.nodes
  name     = "${each.key}.qcow2"
  pool     = "default"
  capacity = each.value.disk_gb * 1073741824

  target = {
    format = { type = "qcow2" }
  }

  backing_store = {
    path   = libvirt_volume.fedora_base.path
    format = { type = "qcow2" }
  }
}

# Extra data disks (RAID pair for storage-node, pgdata for test-server)
resource "libvirt_volume" "extra_disk" {
  for_each = var.extra_disks
  name     = "${each.key}.qcow2"
  pool     = "default"
  capacity = each.value.size_gb * 1073741824

  target = {
    format = { type = "qcow2" }
  }
}

# Cloud-init ISO generation
resource "libvirt_cloudinit_disk" "init" {
  for_each = var.nodes
  name     = "${each.key}-init"

  user_data = templatefile("${path.module}/cloud-init/common.yml.tftpl", {
    hostname  = each.key
    static_ip = each.value.ip
  })

  network_config = file("${path.module}/cloud-init/network.yml.tftpl")

  meta_data = <<-EOF
    instance-id: ${each.key}
    local-hostname: ${each.key}
  EOF
}

# Upload cloud-init ISOs into the pool
resource "libvirt_volume" "cloudinit_volume" {
  for_each = var.nodes
  name     = "${each.key}-cloudinit.iso"
  pool     = "default"

  create = {
    content = {
      url = libvirt_cloudinit_disk.init[each.key].path
    }
  }
}

# VM definitions
resource "libvirt_domain" "node" {
  for_each    = var.nodes
  name        = each.key
  type        = "kvm"
  memory      = each.value.memory
  memory_unit = "MiB"
  vcpu        = each.value.vcpu

  cpu = {
    mode = "host-passthrough"
  }

  os = {
    type         = "hvm"
    type_arch    = "x86_64"
    type_machine = "q35"
    boot_devices = [{ dev = "hd" }]
  }

  features = {
    acpi = true
  }

  devices = {
    disks = concat(
      [
        {
          driver = {
            name = "qemu"
            type = "qcow2"
          }
          source = {
            volume = {
              pool   = libvirt_volume.node_disk[each.key].pool
              volume = libvirt_volume.node_disk[each.key].name
            }
          }
          target = {
            dev = "vda"
            bus = "virtio"
          }
        },
        {
          device = "cdrom"
          driver = {
            name = "qemu"
            type = "raw"
          }
          source = {
            volume = {
              pool   = libvirt_volume.cloudinit_volume[each.key].pool
              volume = libvirt_volume.cloudinit_volume[each.key].name
            }
          }
          target = {
            dev = "sda"
            bus = "sata"
          }
        }
      ],
      [
        for idx, disk_key in local.node_extra_disks[each.key] : {
          driver = {
            name = "qemu"
            type = "qcow2"
          }
          source = {
            volume = {
              pool   = libvirt_volume.extra_disk[disk_key].pool
              volume = libvirt_volume.extra_disk[disk_key].name
            }
          }
          target = {
            dev = "vd${local.dev_letters[idx]}"
            bus = "virtio"
          }
        }
      ]
    )

    interfaces = [
      {
        type  = "network"
        model = { type = "virtio" }
        source = {
          network = { network = "default" }
        }
      },
      {
        type  = "network"
        model = { type = "virtio" }
        source = {
          network = { network = libvirt_network.secos_net.name }
        }
      }
    ]

    consoles = [
      {
        type = "pty"
        target = {
          type = "serial"
          port = 0
        }
      }
    ]

    graphics = [
      {
        vnc = {
          autoport = "yes"
          listen   = "127.0.0.1"
        }
      }
    ]
  }

  running = true
}
