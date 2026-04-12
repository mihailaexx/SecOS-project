resource "libvirt_network" "secos_net" {
  name      = "secos-net"
  autostart = true

  ips = [
    {
      address = "192.168.56.1"
      prefix  = 24
      family  = "ipv4"
    }
  ]
}
