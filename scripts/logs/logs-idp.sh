#!/bin/bash
# Central Keycloak + OpenLDAP events from idp-node.
# Usage: ./scripts/logs/logs-idp.sh [pattern]
#   SINCE=<expr> env overrides time window (default: "1 day ago")

set -euo pipefail

PATTERN="${1:-.*}"
SINCE="${SINCE:-1 day ago}"

vagrant ssh nfs -c "sudo journalctl \
  -D /var/log/journal/remote \
  --since '${SINCE}' \
  -o short-iso \
  _SYSTEMD_UNIT=keycloak.service + _SYSTEMD_UNIT=slapd.service \
  | grep -Ei '${PATTERN}' || true"
