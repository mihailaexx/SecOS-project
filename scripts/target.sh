#!/bin/bash
# Install and configure PostgreSQL on test-server with dedicated data disk

# Dedicated disk for PostgreSQL data (sdb → /var/lib/pgsql)
sudo mkfs.xfs /dev/sdb
sudo mkdir -p /var/lib/pgsql
sudo mount /dev/sdb /var/lib/pgsql
echo '/dev/sdb /var/lib/pgsql xfs defaults 0 0' | sudo tee -a /etc/fstab

# PostgreSQL
sudo dnf install -y https://download.postgresql.org/pub/repos/yum/reporpms/F-42-x86_64/pgdg-fedora-repo-latest.noarch.rpm
sudo dnf -qy module disable postgresql
sudo dnf install -y postgresql16-server postgresql16

sudo chown postgres:postgres /var/lib/pgsql
sudo /usr/pgsql-16/bin/postgresql-16-setup initdb

cat <<'EOF' | sudo tee /var/lib/pgsql/16/data/pg_hba.conf
# TYPE  DATABASE  USER      ADDRESS          METHOD
local   all       postgres                   peer
host    all       dba1      192.168.56.0/24  md5
host    all       all       127.0.0.1/32     md5
EOF

sudo systemctl enable --now postgresql-16

sudo -u postgres /usr/pgsql-16/bin/psql -c "CREATE ROLE dba1 WITH LOGIN PASSWORD 'dba' SUPERUSER;"

cat <<'EOF' | sudo tee /etc/sudoers.d/dba
%dba ALL=(postgres) /usr/pgsql-16/bin/psql
%dba ALL=(root) /usr/bin/systemctl restart postgresql-16
EOF
sudo chmod 440 /etc/sudoers.d/dba

# NFS mount for backups
sudo dnf install -y nfs-utils cronie
sudo mkdir -p /mnt/backups
echo '192.168.56.50:/export/backups /mnt/backups nfs _netdev,defaults 0 0' | sudo tee -a /etc/fstab
sudo mount /mnt/backups

# Backup crons
cat <<'CRON' | sudo tee /etc/cron.d/backup-postgres
0 2 * * * postgres /usr/pgsql-16/bin/pg_dumpall | gzip > /mnt/backups/postgres/pg-$(date +\%F).sql.gz && find /mnt/backups/postgres/ -name "*.sql.gz" -mtime +7 -delete
CRON

# Daily config backup
cat <<'CRON' | sudo tee /etc/cron.d/backup-configs
0 3 * * * root mkdir -p /mnt/backups/configs/test-server && rsync -a /etc/ /mnt/backups/configs/test-server/
CRON
sudo systemctl enable --now crond

# Firewall
sudo dnf install -y firewalld

sudo mkdir -p /etc/firewalld/zones
cat <<'EOF' | sudo tee /etc/firewalld/zones/public.xml
<?xml version="1.0" encoding="utf-8"?>
<zone>
  <short>Public</short>
  <rule family="ipv4">
    <source address="192.168.56.11/32"/>
    <port port="22" protocol="tcp"/>
    <accept/>
  </rule>
  <rule family="ipv4">
    <source address="192.168.56.12/32"/>
    <port port="22" protocol="tcp"/>
    <accept/>
  </rule>
  <rule family="ipv4">
    <source address="192.168.56.11/32"/>
    <port port="5432" protocol="tcp"/>
    <accept/>
  </rule>
  <rule family="ipv4">
    <source address="192.168.56.12/32"/>
    <port port="5432" protocol="tcp"/>
    <accept/>
  </rule>
  <rule family="ipv4">
    <port port="22" protocol="tcp"/>
    <reject/>
  </rule>
</zone>
EOF

sudo systemctl enable --now firewalld
