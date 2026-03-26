#!/bin/bash
# Install and configure Keycloak and OpenLDAP on idp-node

# OpenLDAP
sudo dnf install -y openldap-servers openldap-clients
sudo systemctl enable --now slapd

# Load required LDAP schemas
sudo ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/cosine.ldif
sudo ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/inetorgperson.ldif
sudo ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/nis.ldif

# Create MDB database for dc=bastion,dc=local
sudo mkdir -p /var/lib/ldap
sudo chown ldap:ldap /var/lib/ldap

cat <<'EOF' | sudo ldapadd -Y EXTERNAL -H ldapi:///
dn: olcDatabase=mdb,cn=config
objectClass: olcDatabaseConfig
objectClass: olcMdbConfig
olcDatabase: mdb
olcDbDirectory: /var/lib/ldap
olcSuffix: dc=bastion,dc=local
olcRootDN: cn=admin,dc=bastion,dc=local
olcRootPW: admin
olcDbIndex: objectClass eq
olcDbIndex: uid eq
olcAccess: to * by * read
EOF

# Populate LDAP directory
cat <<'EOF' | ldapadd -x -D "cn=admin,dc=bastion,dc=local" -w admin
dn: dc=bastion,dc=local
objectClass: top
objectClass: dcObject
objectClass: organization
o: Bastion Local
dc: bastion

dn: ou=People,dc=bastion,dc=local
objectClass: top
objectClass: organizationalUnit
ou: People

dn: ou=Groups,dc=bastion,dc=local
objectClass: top
objectClass: organizationalUnit
ou: Groups

dn: uid=m.bulushev,ou=People,dc=bastion,dc=local
objectClass: top
objectClass: inetOrgPerson
objectClass: posixAccount
uid: m.bulushev
cn: Mikhail Bulushev
sn: Bulushev
uidNumber: 1001
gidNumber: 2000
homeDirectory: /home/m.bulushev
loginShell: /bin/bash

dn: uid=admin1,ou=People,dc=bastion,dc=local
objectClass: top
objectClass: inetOrgPerson
objectClass: posixAccount
uid: admin1
cn: Admin One
sn: Admin
uidNumber: 1002
gidNumber: 2001
homeDirectory: /home/admin1
loginShell: /bin/bash

dn: uid=dba1,ou=People,dc=bastion,dc=local
objectClass: top
objectClass: inetOrgPerson
objectClass: posixAccount
uid: dba1
cn: DBA One
sn: DBA
uidNumber: 1003
gidNumber: 2002
homeDirectory: /home/dba1
loginShell: /bin/bash

dn: cn=bastion-users,ou=Groups,dc=bastion,dc=local
objectClass: top
objectClass: posixGroup
cn: bastion-users
gidNumber: 2000
memberUid: m.bulushev
memberUid: admin1
memberUid: dba1

dn: cn=bastion-admins,ou=Groups,dc=bastion,dc=local
objectClass: top
objectClass: posixGroup
cn: bastion-admins
gidNumber: 2001
memberUid: admin1

dn: cn=dba,ou=Groups,dc=bastion,dc=local
objectClass: top
objectClass: posixGroup
cn: dba
gidNumber: 2002
memberUid: dba1
EOF

# Java (required by Keycloak)
sudo dnf install -y java-21-openjdk-headless

# Keycloak binary
KEYCLOAK_VERSION="26.5.4"
cd /tmp
curl -sLO "https://github.com/keycloak/keycloak/releases/download/${KEYCLOAK_VERSION}/keycloak-${KEYCLOAK_VERSION}.tar.gz"
sudo tar -xzf "keycloak-${KEYCLOAK_VERSION}.tar.gz" -C /opt
sudo mv "/opt/keycloak-${KEYCLOAK_VERSION}" /opt/keycloak

sudo useradd -r -s /sbin/nologin -d /opt/keycloak keycloak
sudo chown -R keycloak:keycloak /opt/keycloak

# Realm import file
sudo mkdir -p /opt/keycloak/data/import
cat <<'EOF' | sudo tee /opt/keycloak/data/import/bastion-realm.json
{
  "realm": "bastion",
  "enabled": true,
  "roles": {
    "realm": [
      {
        "name": "bastion-pam-authentication",
        "composite": false,
        "clientRole": false
      }
    ]
  },
  "clientScopes": [
    {
      "name": "pam_roles",
      "protocol": "openid-connect",
      "attributes": {
        "include.in.token.scope": "true",
        "display.on.consent.screen": "false"
      },
      "protocolMappers": [
        {
          "name": "pam roles",
          "protocol": "openid-connect",
          "protocolMapper": "oidc-usermodel-realm-role-mapper",
          "config": {
            "multivalued": "true",
            "claim.name": "pam_roles",
            "jsonType.label": "String",
            "id.token.claim": "false",
            "access.token.claim": "true",
            "userinfo.token.claim": "false"
          }
        }
      ]
    }
  ],
  "clients": [
    {
      "clientId": "bastion-ssh",
      "enabled": true,
      "publicClient": false,
      "secret": "bastion-ssh-secret",
      "redirectUris": ["urn:ietf:wg:oauth:2.0:oob"],
      "standardFlowEnabled": true,
      "directAccessGrantsEnabled": true,
      "serviceAccountsEnabled": false,
      "consentRequired": false,
      "fullScopeAllowed": false,
      "attributes": {
        "access.token.signed.response.alg": "RS256"
      },
      "defaultClientScopes": ["pam_roles"]
    }
  ],
  "scopeMappings": [
    {
      "client": "bastion-ssh",
      "roles": ["bastion-pam-authentication"]
    }
  ],
  "users": [
    {
      "username": "m.bulushev",
      "enabled": true,
      "firstName": "Mikhail",
      "lastName": "Bulushev",
      "email": "m.bulushev@bastion.local",
      "emailVerified": true,
      "credentials": [{ "type": "password", "value": "password", "temporary": false }],
      "realmRoles": ["bastion-pam-authentication"]
    },
    {
      "username": "admin1",
      "enabled": true,
      "firstName": "Admin",
      "lastName": "One",
      "email": "admin1@bastion.local",
      "emailVerified": true,
      "credentials": [{ "type": "password", "value": "password", "temporary": false }],
      "realmRoles": ["bastion-pam-authentication"]
    },
    {
      "username": "dba1",
      "enabled": true,
      "firstName": "DBA",
      "lastName": "One",
      "email": "dba1@bastion.local",
      "emailVerified": true,
      "credentials": [{ "type": "password", "value": "password", "temporary": false }],
      "realmRoles": ["bastion-pam-authentication"]
    }
  ]
}
EOF
sudo chown -R keycloak:keycloak /opt/keycloak/data

# Keycloak configuration
cat <<'EOF' | sudo tee /opt/keycloak/conf/keycloak.conf
hostname=idp-node.bastion.local
hostname-strict=false
http-enabled=true
http-port=8080
health-enabled=true
db=dev-file
EOF

cat <<'EOF' | sudo tee /etc/systemd/system/keycloak.service
[Unit]
Description=Keycloak Identity Provider
After=network.target slapd.service
Wants=slapd.service

[Service]
Type=simple
User=keycloak
Group=keycloak
Environment=KC_BOOTSTRAP_ADMIN_USERNAME=admin
Environment=KC_BOOTSTRAP_ADMIN_PASSWORD=admin
ExecStart=/opt/keycloak/bin/kc.sh start-dev --import-realm
ExecStop=/opt/keycloak/bin/kc.sh stop
WorkingDirectory=/opt/keycloak
Restart=on-failure
RestartSec=15
StandardOutput=journal
StandardError=journal
SyslogIdentifier=keycloak

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now keycloak

# Firewall
sudo dnf install -y firewalld

sudo mkdir -p /etc/firewalld/zones
cat <<'EOF' | sudo tee /etc/firewalld/zones/internal-bastion.xml
<?xml version="1.0" encoding="utf-8"?>
<zone>
  <short>Internal Bastion</short>
  <source address="192.168.56.0/24"/>
  <port port="8080" protocol="tcp"/>
  <port port="389" protocol="tcp"/>
</zone>
EOF

cat <<'EOF' | sudo tee /etc/firewalld/zones/public.xml
<?xml version="1.0" encoding="utf-8"?>
<zone>
  <short>Public</short>
  <service name="ssh"/>
  <port port="8080" protocol="tcp"/>
</zone>
EOF

sudo systemctl enable --now firewalld

# NFS mount for backups
sudo dnf install -y nfs-utils cronie
sudo mkdir -p /mnt/backups
echo '192.168.56.50:/export/backups /mnt/backups nfs _netdev,defaults 0 0' | sudo tee -a /etc/fstab
sudo mount /mnt/backups

# Backup crons
cat <<'CRON' | sudo tee /etc/cron.d/backup-ldap
0 2 * * * root slapcat | gzip > /mnt/backups/ldap/ldap-$(date +\%F).ldif.gz && find /mnt/backups/ldap/ -name "*.ldif.gz" -mtime +7 -delete
CRON

# Daily Keycloak realm export
cat <<'CRON' | sudo tee /etc/cron.d/backup-keycloak
30 2 * * * root /opt/keycloak/bin/kc.sh export --dir /mnt/backups/keycloak/ --realm bastion && find /mnt/backups/keycloak/ -name "*.json" -mtime +7 -delete
CRON

# Daily config backup
cat <<'CRON' | sudo tee /etc/cron.d/backup-configs
0 3 * * * root mkdir -p /mnt/backups/configs/idp-node && rsync -a /etc/ /mnt/backups/configs/idp-node/
CRON
sudo systemctl enable --now crond
