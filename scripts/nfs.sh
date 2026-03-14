#!/bin/bash
# Install and configure NFS server on storage-node

sudo dnf install -y nfs-utils

sudo mkdir -p /export/home
sudo chmod 755 /export/home

# Create user home directories on NFS share
for u in m.bulushev admin1 dba1; do
  sudo mkdir -p /export/home/$u
  sudo chmod 700 /export/home/$u
done
sudo chown 1001:2000 /export/home/m.bulushev
sudo chown 1002:2001 /export/home/admin1
sudo chown 1003:2002 /export/home/dba1

cat <<'EOF' | sudo tee /etc/exports
/export/home 192.168.56.0/24(rw,sync,no_subtree_check,no_root_squash)
EOF

sudo exportfs -rav
sudo systemctl enable --now nfs-server

# --- Firewall ---
sudo dnf install -y firewalld

sudo mkdir -p /etc/firewalld/zones
cat <<'EOF' | sudo tee /etc/firewalld/zones/internal-bastion.xml
<?xml version="1.0" encoding="utf-8"?>
<zone>
  <short>Internal Bastion</short>
  <source address="192.168.56.0/24"/>
  <service name="nfs"/>
  <service name="rpc-bind"/>
  <service name="mountd"/>
</zone>
EOF

sudo systemctl enable --now firewalld
