#!/bin/bash
# Install and configure Keycloak and OpenLDAP on idp-node

# OpenLDAP
sudo dnf install -y openldap-servers openldap-clients
sudo systemctl enable --now slapd

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
  "realm": "bastion-realm",
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
      "credentials": [{ "type": "password", "value": "password", "temporary": false }],
      "realmRoles": ["bastion-pam-authentication"]
    },
    {
      "username": "admin1",
      "enabled": true,
      "credentials": [{ "type": "password", "value": "password", "temporary": false }],
      "realmRoles": ["bastion-pam-authentication"]
    },
    {
      "username": "dba1",
      "enabled": true,
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
