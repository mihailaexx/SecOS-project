#!/bin/bash
# Central auditd events across the fleet, filtered by audit key.
# Usage: ./scripts/logs/logs-audit.sh <key> [host]
#   key   — auditd rule key (identity, privilege, sshd, pg_hba, ...)
#   host  — optional hostname substring (e.g. bastion, idp-node)
#   SINCE=<expr> env overrides time window (default: "1 day ago")

set -euo pipefail

KEY="${1:?usage: logs-audit.sh <key> [host]}"
HOST="${2:-}"
SINCE="${SINCE:-1 day ago}"

vagrant ssh nfs -c "sudo journalctl \
  -D /var/log/journal/remote \
  --since '${SINCE}' \
  -o short-iso \
  SYSLOG_IDENTIFIER=audisp-syslog \
  | grep -E 'key=\"?${KEY}\"?' \
  | { [[ -n '${HOST}' ]] && grep -F '${HOST}' || cat; } || true"
