#!/bin/bash
# Ensure the NetBox role and database exist on the bundled PostgreSQL.
#
# The postgres-init bootstrap script only runs when PostgreSQL initializes
# its data directory for the first time, so enabling NetBox on a release
# whose PostgreSQL already holds data needs this provisioning path. The
# statements are idempotent and reduce to no-ops on fresh installs, where
# the bootstrap has already created both objects.
#
# Required environment:
#   POD_NAMESPACE — namespace of the bundled PostgreSQL deployment

set -euo pipefail

ns="${POD_NAMESPACE:?POD_NAMESPACE is required}"
deadline=$(( $(date +%s) + 600 ))

find_pod() {
  oc -n "${ns}" get pod -l app=postgres \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true
}

pod=""
while [ "$(date +%s)" -lt "${deadline}" ]; do
  candidate="$(find_pod)"
  if [ -n "${candidate}" ] && oc -n "${ns}" exec "${candidate}" -- psql -tAc 'select 1' >/dev/null 2>&1; then
    pod="${candidate}"
    break
  fi
  echo "Waiting for PostgreSQL to accept connections..."
  sleep 5
done
if [ -z "${pod}" ]; then
  echo "ERROR: bundled PostgreSQL was not reachable in time" >&2
  exit 1
fi

# psql connects through the pod-local socket with peer authentication as
# the PostgreSQL superuser; each statement runs only when its target is
# missing.
oc -n "${ns}" exec -i "${pod}" -- psql <<'.'
SELECT 'CREATE ROLE netbox' WHERE NOT EXISTS
  (SELECT FROM pg_roles WHERE rolname = 'netbox')\gexec
SELECT 'CREATE DATABASE netbox OWNER netbox' WHERE NOT EXISTS
  (SELECT FROM pg_database WHERE datname = 'netbox')\gexec
.
