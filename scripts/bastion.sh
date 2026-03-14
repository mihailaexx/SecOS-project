#!/bin/bash
# Configure bastion's node

# Packages (no build tools needed -- using precompiled pam-keycloak-oidc)
sudo dnf install -y nfs-utils sssd sssd-ldap oddjob-mkhomedir autofs

# Autofs for NFS home directories
cat <<'EOF' | sudo tee /etc/auto.master.d/home.autofs
/home /etc/auto.home
EOF

cat <<'EOF' | sudo tee /etc/auto.home
* -rw,sync 192.168.56.50:/export/home/&
EOF

sudo systemctl enable --now autofs

# SSSD (LDAP user/group resolution)
cat <<'EOF' | sudo tee /etc/sssd/sssd.conf
[sssd]
services = nss, pam
domains = bastion.local

[domain/bastion.local]
id_provider = ldap
auth_provider = ldap
ldap_uri = ldap://192.168.56.20
ldap_search_base = dc=bastion,dc=local
ldap_id_use_start_tls = False
cache_credentials = True
enumerate = True
EOF

sudo chmod 600 /etc/sssd/sssd.conf
sudo systemctl enable --now sssd

sudo authselect select sssd with-mkhomedir --force
sudo systemctl enable --now oddjobd

# pam-keycloak-oidc (official precompiled binary r1.3.0)
sudo mkdir -p /opt/pam-keycloak-oidc
curl -sL -o /opt/pam-keycloak-oidc/pam-keycloak-oidc \
  https://github.com/zhaow-de/pam-keycloak-oidc/releases/download/r1.3.0/pam-keycloak-oidc.linux-amd64
sudo chmod +x /opt/pam-keycloak-oidc/pam-keycloak-oidc

# TOML config (must sit next to the binary with .tml extension)
cat <<'EOF' | sudo tee /opt/pam-keycloak-oidc/pam-keycloak-oidc.tml
client-id="bastion-ssh"
client-secret="bastion-ssh-secret"
redirect-url="urn:ietf:wg:oauth:2.0:oob"
scope="pam_roles"
vpn-user-role="bastion-pam-authentication"
endpoint-auth-url="http://192.168.56.20:8080/realms/bastion-realm/protocol/openid-connect/auth"
endpoint-token-url="http://192.168.56.20:8080/realms/bastion-realm/protocol/openid-connect/token"
username-format="%s"
access-token-signing-method="RS256"
xor-key="scmi"
otp-only=false
EOF

# PAM stack for sshd (uses pam_exec.so to invoke the binary)
cat <<'EOF' | sudo tee /etc/pam.d/sshd
#%PAM-1.0
auth       [success=1 default=ignore]  pam_exec.so expose_authtok log=/var/log/pam-keycloak-oidc.log /opt/pam-keycloak-oidc/pam-keycloak-oidc
auth       requisite                   pam_deny.so
auth       required                    pam_permit.so
account    required                    pam_nologin.so
account    required                    pam_permit.so
session    required                    pam_limits.so
session    required                    pam_unix.so
session    optional                    pam_mkhomedir.so
EOF

# SSHD config for keyboard-interactive auth
sudo sed -i 's/^#\?UsePAM.*/UsePAM yes/' /etc/ssh/sshd_config
sudo sed -i 's/^#\?ChallengeResponseAuthentication.*/ChallengeResponseAuthentication yes/' /etc/ssh/sshd_config
sudo sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
sudo sed -i 's/^#\?PubkeyAuthentication.*/PubkeyAuthentication no/' /etc/ssh/sshd_config
grep -q '^AuthenticationMethods' /etc/ssh/sshd_config || echo 'AuthenticationMethods keyboard-interactive' | sudo tee -a /etc/ssh/sshd_config
grep -q '^KbdInteractiveAuthentication' /etc/ssh/sshd_config || echo 'KbdInteractiveAuthentication yes' | sudo tee -a /etc/ssh/sshd_config
sudo systemctl restart sshd

# Groups
sudo groupadd -g 2000 bastion-users
sudo groupadd -g 2001 bastion-admins
sudo groupadd -g 2002 dba

# Users
sudo useradd -m -g bastion-users -s /bin/bash m.bulushev
sudo usermod -aG bastion-users m.bulushev

sudo useradd -m -g bastion-admins -s /bin/bash admin1
sudo usermod -aG bastion-users,bastion-admins admin1

sudo useradd -m -g dba -s /bin/bash dba1
sudo usermod -aG bastion-users,dba dba1

# Sudoers
cat <<'EOF' | sudo tee /etc/sudoers.d/bastion-admins
%bastion-admins ALL=(root) /usr/bin/systemctl restart sssd
%bastion-admins ALL=(root) /usr/bin/systemctl restart haproxy
%bastion-admins ALL=(root) /usr/sbin/exportfs -ra
EOF
sudo chmod 440 /etc/sudoers.d/bastion-admins

# Firewall
sudo dnf install -y firewalld

sudo mkdir -p /etc/firewalld/zones
cat <<'EOF' | sudo tee /etc/firewalld/zones/public.xml
<?xml version="1.0" encoding="utf-8"?>
<zone>
  <short>Public</short>
  <rule family="ipv4">
    <source address="192.168.56.10/32"/>
    <port port="22" protocol="tcp"/>
    <accept/>
  </rule>
  <rule family="ipv4">
    <port port="22" protocol="tcp"/>
    <reject/>
  </rule>
</zone>
EOF

sudo systemctl enable --now firewalld
