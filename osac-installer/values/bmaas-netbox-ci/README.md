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
| `netbox-credentials` | `osac-infra` | `secret_key`, `superuser_password`, `db_password`, `api_token_peppers`, `email_password` (empty — see below) |
| `netbox-api-token` | `osac` | `token` (consumed by bare-metal-fulfillment-operator) |

### api_token_peppers

NetBox 4.7 requires `API_TOKEN_PEPPERS` to be configured for all token
operations (including v1 token creation). The credentials-init Job generates a
random pepper and writes it as a JSON dict: `{"1": "<64-char hex>"}`. NetBox
loads this from `existingSecret` at startup and uses it for HMAC signing.

### email_password

The NetBox chart mounts `email_password` from `existingSecret` as a volume
item unconditionally — even when email sending is not configured. The pod
fails to start with `FailedMount` if the key is absent. The credentials-init
Job therefore creates the key with an empty value; it is never read by NetBox
in a CI environment that does not send email.

### Token format (NetBox 4.7)

NetBox 4.7 uses v2 HMAC tokens. The token value stored in `netbox-api-token`
and written to the `tokenFile` has the format `nbt_{key}.{plaintext}` — it
must be presented as `Authorization: Bearer nbt_{key}.{plaintext}` in API
requests. The seed Job creates the token via `manage.py shell` inside the
running NetBox pod (the only place where both parts of the token are available
in memory simultaneously) and captures the full value before the Python session
ends.

## OpenShift Security Context Constraints

The [netbox-community/netbox](https://github.com/netbox-community/netbox-chart)
chart is a Bitnami-based chart that hardcodes `runAsUser: 1000`,
`fsGroup: 1000`, and sets `seccompProfile: RuntimeDefault` annotations on its
containers. These values are rejected by OpenShift's built-in SCCs:

- `restricted-v2` rejects UID 1000 and fsGroup 1000 (namespace UID range
  starts at ~1000770000).
- `anyuid` rejects the chart's seccomp annotations
  (`seccomp.security.alpha.kubernetes.io/*`).

The `osac-infra` chart therefore creates a dedicated
`SecurityContextConstraints` object (`osac-infra-netbox`) that permits:

- **`runAsUser.type: RunAsAny`** — allows the Bitnami hardcoded UID 1000.
- **`fsGroup.type: RunAsAny`** — allows fsGroup 1000.
- **`seLinuxContext.type: RunAsAny`** — lets OpenShift assign the correct
  SELinux label automatically rather than requiring the chart to specify one.
- **`seccompProfiles: [runtime/default, docker/default]`** — allows the
  seccomp annotations the chart sets.

The SCC is scoped to `system:serviceaccount:osac-infra:osac-infra-netbox` only,
minimising its blast radius to a single service account in the `osac-infra`
namespace.

## CI / GitHub Actions

A `workflow_dispatch`-only workflow
(`.github/workflows/e2e-bmaas-netbox-full-install.yml`) exercises this
profile against the `bmaas_netbox` E2E test suite. It is not a required
check.
