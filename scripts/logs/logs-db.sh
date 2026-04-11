#!/bin/bash
# Central PostgreSQL events from test-server.
# Usage: ./scripts/logs/logs-db.sh [pattern]
#   SINCE=<expr> env overrides time window (default: "1 day ago")

set -euo pipefail

PATTERN="${1:-.*}"
SINCE="${SINCE:-1 day ago}"

vagrant ssh nfs -c "sudo journalctl \
  -D /var/log/journal/remote \
  --since '${SINCE}' \
  -o short-iso \
  _SYSTEMD_UNIT=postgresql-16.service \
  | grep -Ei '${PATTERN}' || true"
