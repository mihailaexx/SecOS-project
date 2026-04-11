#!/bin/bash
# Central SSH + PAM + pam-keycloak-oidc auth events.
# Usage: ./scripts/logs/logs-ssh.sh [user-or-pattern]
#   SINCE=<expr> env overrides time window (default: "1 day ago")

set -euo pipefail

PATTERN="${1:-.*}"
SINCE="${SINCE:-1 day ago}"

vagrant ssh nfs -c "sudo journalctl \
  -D /var/log/journal/remote \
  --since '${SINCE}' \
  -o short-iso \
  _SYSTEMD_UNIT=sshd.service + SYSLOG_IDENTIFIER=sshd + SYSLOG_IDENTIFIER=pam-keycloak-oidc \
  | grep -Ei '${PATTERN}' || true"
