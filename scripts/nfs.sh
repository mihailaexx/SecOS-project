#!/bin/bash
# Install and configure NFS server on storage-node with RAID1

sudo dnf install -y nfs-utils mdadm cronie

# RAID1 Setup (sdb + sdc → md0)
sudo mdadm --create /dev/md0 --level=1 --raid-devices=2 --run /dev/sdb /dev/sdc
sudo mkfs.xfs /dev/md0

sudo mkdir -p /export/home
sudo mount /dev/md0 /export/home

# Persist RAID and mount
sudo mdadm --detail --scan | sudo tee -a /etc/mdadm.conf
echo '/dev/md0 /export/home xfs defaults 0 0' | sudo tee -a /etc/fstab

sudo chmod 755 /export/home

# Create user home directories on NFS share
for u in m.bulushev admin1 dba1; do
  sudo mkdir -p /export/home/$u
  sudo chmod 700 /export/home/$u
done
sudo chown 1001:2000 /export/home/m.bulushev
sudo chown 1002:2001 /export/home/admin1
sudo chown 1003:2002 /export/home/dba1

# Backup directories (on RAID1 array)
sudo mkdir -p /export/backups/{postgres,ldap,keycloak,configs,homes}

# NFS Exports
cat <<'EOF' | sudo tee /etc/exports
/export/home 192.168.56.0/24(rw,sync,no_subtree_check,no_root_squash)
/export/backups 192.168.56.0/24(rw,sync,no_subtree_check,no_root_squash)
EOF

sudo exportfs -rav
sudo systemctl enable --now nfs-server

# Weekly home backup cron
cat <<'CRON' | sudo tee /etc/cron.d/backup-homes
0 2 * * 0 root tar czf /export/backups/homes/homes-$(date +\%F).tar.gz -C / export/home/ && find /export/backups/homes/ -name "*.tar.gz" -mtime +7 -delete
CRON
sudo systemctl enable --now crond

# Firewall
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
