# bmaas-netbox-ci profile

Installer profile for the BMaaS NetBox E2E test flavor. It inherits
`bmaas-ci` as its base and overlays only the values needed to swap the
bare-metal inventory backend from Metal3/BMH to
[NetBox](https://netbox.dev/).

## What this profile does

- Deploys NetBox via the `netbox-community/netbox` Helm subchart into the
  `osac-infra` namespace.
- Generates all NetBox credentials at install time (no manual secret
  bootstrap required) via a `pre-install` Kubernetes Job.
- Registers the generated API token with NetBox and writes it as
  `netbox-api-token` into the `osac` namespace, where the
  bare-metal-fulfillment-operator mounts it as its inventory credential.
- Disables the Metal3 inventory backend (`bmf.metal3.enabled: false`).
- Enables the NetBox inventory backend (`bmf.netbox`).

## Inventory configuration

The bare-metal-fulfillment-operator reads its inventory backend from a
mounted `inventory.yaml` file. For this profile the file contains:

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

> **Note:** `hostClass` must be `"metal3"` — a hard requirement of
> `NewNetBoxClient`. The NetBox client uses Metal3 for BareMetalHost
> lifecycle management while NetBox supplies the hardware inventory.

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
check.
