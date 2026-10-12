#!/usr/bin/env bash
set -euo pipefail

# Provision a NetBox API token via POST /api/users/tokens/provision/ and write
# it to a Secret in the operator namespace. Idempotent: exits 0 if the Secret
# already exists (e.g. on upgrade).
#
# Required env vars (set by the Job spec):
#   OPERATOR_NS       — namespace where the operator reads the token Secret
#   SECRET_NAME       — name of the Secret to create
#   NETBOX_SVC        — base URL of the NetBox service
#   NETBOX_USERNAME   — NetBox superuser username
#
# Required volume mount:
#   /credentials/password — superuser password (from osac-infra-netbox-superuser Secret)

PASS="$(cat /credentials/password)"

if oc -n "${OPERATOR_NS}" get secret "${SECRET_NAME}" > /dev/null 2>&1; then
  echo "Secret ${SECRET_NAME} already exists — skipping."
  exit 0
fi

until curl -sf "${NETBOX_SVC}/login/" > /dev/null; do
  echo "Waiting for NetBox..."
  sleep 5
done

PAYLOAD=$(python3 -c "import json,sys; print(json.dumps({'username':sys.argv[1],'password':sys.argv[2]}))" \
  "${NETBOX_USERNAME}" "${PASS}")

RESP=$(curl -sf -X POST "${NETBOX_SVC}/api/users/tokens/provision/" \
  -H "Content-Type: application/json" \
  --data-raw "${PAYLOAD}")

KEY=$(echo "${RESP}" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['key'])")
TOK=$(echo "${RESP}" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['token'])")
TOKEN="nbt_${KEY}.${TOK}"

oc -n "${OPERATOR_NS}" create secret generic "${SECRET_NAME}" \
  --from-literal=token="${TOKEN}"

echo "Secret ${SECRET_NAME} written to namespace ${OPERATOR_NS}."
