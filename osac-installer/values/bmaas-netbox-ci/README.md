# bmaas-netbox-ci profile

BMaaS E2E profile using [NetBox](https://netbox.dev/) as the bare-metal
inventory backend. Inherits `bmaas-ci` and overlays only what differs.

## What it does

- Deploys NetBox (`netbox-community/netbox` subchart) into `osac-infra`.
- Provisions an API token via `POST /api/users/tokens/provision/` and writes
  it as `netbox-api-token` into `osac` for the bare-metal-fulfillment-operator.
- Disables Metal3 (`bmf.metal3.enabled: false`) and points the operator's
  inventory backend at NetBox (`bmf.netbox`).

## Install

```bash
make install PLATFORM=openshift PROFILE=bmaas-netbox-ci NS=osac
```

## Database

NetBox does not deploy its own database. It uses the shared PostgreSQL
deployed by `osac-infra`'s `bundledPostgres` (the `postgres` service in
`osac-infra`):

- `postgresql.enabled: false` keeps the subchart's Bitnami PostgreSQL
  undeployed; `externalDatabase.*` points NetBox at the `postgres` service.
- The bundled PostgreSQL accepts certificate-only client authentication,
  so `osac-infra` issues the `postgres-client-netbox` certificate and its
  bootstrap script creates the matching `netbox` user and database.
- The client certificate and CA are mounted into the NetBox, worker, and
  housekeeping pods at `/secrets/database-client` and wired through
  `externalDatabase.options` (`sslmode=verify-full`).

## Credentials

The NetBox chart auto-generates the remaining credential secrets on first
install.

| Secret | Namespace | Contents |
|--------|-----------|----------|
| `osac-infra-netbox` | `osac-infra` | `secret_key` |
| `osac-infra-netbox-superuser` | `osac-infra` | `username`, `password` |
| `postgres-client-cert-netbox` | `osac-infra` | TLS client certificate for the shared PostgreSQL |
| `netbox-api-token` | `osac` | `token` — v2 HMAC token for the operator |

`apiTokenPeppers` is set directly in chart values. NetBox 4.7 requires it for
all token operations; a fixed CI string is acceptable for a test-only deployment.

## Token format

NetBox 4.7 issues v2 HMAC tokens in the form `nbt_{key}.{plaintext}`,
presented as `Authorization: Bearer nbt_{key}.{plaintext}`. The seed Job
calls `/api/users/tokens/provision/` (no prior auth required), parses the
JSON response, and stores the full value in `netbox-api-token`. The Job is
idempotent — if the Secret already exists it exits immediately.

## Inventory configuration

The bare-metal-fulfillment-operator reads its inventory backend from a
mounted `inventory.yaml`:

```yaml
name: netbox-inventory
type: netbox
options:
  netbox:
    url: "http://osac-infra-netbox.osac-infra.svc.cluster.local"
    tokenFile: "<path where netbox-api-token is mounted>"
    allowInsecureHTTP: true
hostClass: metal3
```

`hostClass: metal3` is a hard requirement of `NewNetBoxClient` — NetBox
supplies hardware inventory while Metal3 handles BareMetalHost lifecycle.

## OpenShift SCC

The Bitnami chart hardcodes `runAsUser: 1000` and `fsGroup: 1000`, which
`restricted-v2` rejects, and sets seccomp annotations that `anyuid` rejects.
A dedicated `SecurityContextConstraints` object (`osac-infra-netbox`) grants
`RunAsAny` for user/fsGroup/seLinux and allows seccomp, scoped to the single
`osac-infra-netbox` service account.
