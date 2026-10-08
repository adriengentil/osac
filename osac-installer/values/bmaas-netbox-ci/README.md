# bmaas-netbox-ci profile

Installer profile for the BMaaS NetBox E2E test flavor. It inherits
`bmaas-ci` as its base and overlays only the values needed to swap the
bare-metal inventory backend from Metal3/BMH to
[NetBox](https://netbox.dev/).

This profile is part of the [OSAC-6196](https://redhat.atlassian.net/browse/OSAC-6196)
epic (NetBox E2E test infrastructure). It requires the NetBox inventory
client in the bare-metal-fulfillment-operator (OSAC-4346) to be deployed
before end-to-end tests are meaningful.

## What this profile does

- Deploys NetBox via the `netbox-community/netbox` Helm subchart into the
  `osac-infra` namespace.
- Generates all NetBox credentials at install time (no manual secret
  bootstrap required) via a `pre-install` Kubernetes Job.
- Registers the generated API token with NetBox and writes it as
  `netbox-api-token` into the `osac` namespace, where the
  bare-metal-fulfillment-operator mounts it as its inventory credential.
- Disables the Metal3 inventory backend (`bmf.metal3.enabled: false`).
- Enables the NetBox inventory backend (`bmf.netbox`) — takes effect once
  OSAC-6198 adds `bmf.netbox` support to the osac chart.

## Install

From `osac-installer/`:

```bash
make install PLATFORM=openshift PROFILE=bmaas-netbox-ci NS=osac
```

The Makefile layers `values/bmaas-ci/{infra,instance}.yaml` as the base
and applies `values/bmaas-netbox-ci/{infra,instance}.yaml` on top.

## Credentials

All credentials are generated randomly by a `pre-install` Job on first
install and stored in the `netbox-credentials` Secret in the `osac-infra`
namespace. The Job is idempotent — reinstalls and upgrades preserve the
existing Secret.

| Secret | Namespace | Contents |
|--------|-----------|----------|
| `netbox-credentials` | `osac-infra` | `secret_key`, `superuser_password`, `db_password`, `api_token` |
| `netbox-api-token` | `osac` | `token` (consumed by bare-metal-fulfillment-operator) |

## CI / GitHub Actions

A `workflow_dispatch`-only workflow
(`.github/workflows/e2e-bmaas-netbox-full-install.yml`) exercises this
profile against the `bmaas_netbox` E2E test suite. It is not a required
check. Automatic triggers will be added once T3–T5 (OSAC-6198–OSAC-6200)
are complete.

## Dependencies

| Ticket | Description | Status |
|--------|-------------|--------|
| [OSAC-6197](https://redhat.atlassian.net/browse/OSAC-6197) | This PR — installer + profile | ✓ |
| [OSAC-6198](https://redhat.atlassian.net/browse/OSAC-6198) | T3: operator Helm config for NetBox inventory | Pending |
| [OSAC-6199](https://redhat.atlassian.net/browse/OSAC-6199) | T4: NetBox device fixture helper for E2E tests | Pending |
| [OSAC-6200](https://redhat.atlassian.net/browse/OSAC-6200) | T5: `bmaas_netbox` E2E test flavor | Pending |
