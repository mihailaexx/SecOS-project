#!/bin/bash
# Install and configure HAProxy on lb-node

# Install HAProxy
sudo dnf install -y haproxy

# PAM config for HAProxy stats auth
cat <<'EOF' | sudo tee /etc/haproxy/haproxy.cfg
global
    log /dev/log local0
    chroot /var/lib/haproxy
    stats socket /var/lib/haproxy/stats
    user haproxy
    group haproxy
    daemon

defaults
    mode tcp
    log global
    timeout connect 5s
    timeout client 30s
    timeout server 30s

frontend ssh_front
    bind 192.168.56.10:22
    default_backend ssh_bastions

backend ssh_bastions
    balance roundrobin
    server bastion-01 192.168.56.11:22 check
    server bastion-02 192.168.56.12:22 check
EOF

# Free port 22 for HAProxy by binding sshd only to the Vagrant NAT interface
ETH0_IP=$(ip -4 addr show enp0s3 | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
sudo sed -i '/^#\?ListenAddress/d' /etc/ssh/sshd_config
echo -e "ListenAddress ${ETH0_IP}\nListenAddress 127.0.0.1" | sudo tee -a /etc/ssh/sshd_config
sudo systemctl restart sshd

sudo setsebool -P haproxy_connect_any 1
sudo systemctl enable --now haproxy

# Firewall
sudo dnf install -y firewalld

sudo mkdir -p /etc/firewalld/zones
cat <<'EOF' | sudo tee /etc/firewalld/zones/public.xml
<?xml version="1.0" encoding="utf-8"?>
<zone>
  <short>Public</short>
  <service name="ssh"/>
</zone>
EOF

sudo systemctl enable --now firewalld

# NFS mount for backups
sudo dnf install -y nfs-utils
sudo mkdir -p /mnt/backups
echo '192.168.56.50:/export/backups /mnt/backups nfs defaults 0 0' | sudo tee -a /etc/fstab
sudo mount /mnt/backups

# Daily config backup
cat <<'CRON' | sudo tee /etc/cron.d/backup-configs
0 3 * * * root mkdir -p /mnt/backups/configs/lb-node && rsync -a /etc/ /mnt/backups/configs/lb-node/
CRON
