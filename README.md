# terraform-enderlane-core

Declare an entire [Enderlane](https://www.enderlane.com) tenant's release
configuration as code — so a team can stand up (and version) its whole release
setup without clicking through the UI.

Enderlane is a release-management product. This module provisions, in one
declarative block:

- **Edge provider configs** — Cloudflare KV / AWS CloudFront KVS credentials a
  promotion writes its release pointer to.
- **Lane groups** — a family of things shipped together — each with its
  **lanes** (deployable apps/components) and, optionally, a per-group **stage**
  override progression.
- **Tenant-default stages** — the shared ordered progression (e.g. `alpha →
  bravo → charlie`) that any group without its own override inherits.
- **Gate chain configs** — ordered gate steps (approval / freeze / soak /
  dependency) attached to a transition, tenant-wide or per group/lane.
- **Field-set presets** — templates describing what metadata a unit carries —
  plus **unit-kind → preset mappings** choosing which preset validates a unit
  kind, at tenant / group / lane scope.

Built on the official **[`enderlane`](https://registry.terraform.io/providers/enderlane/enderlane)**
Terraform provider: every entity is a first-class provider resource with real
plan/apply/drift semantics.

> **Vocabulary note.** Enderlane's v2 API (and this module) use *lane group*,
> *lane*, *stage*. The same entities were historically *application group*,
> *application*, *release group*; a lane group **is** an application group (same
> row, same id).

## Quick start

```hcl
terraform {
  required_providers {
    enderlane = {
      source  = "enderlane/enderlane"
      version = ">= 0.1.0"
    }
  }
}

# The provider reads ENDERLANE_API_KEY / ENDERLANE_API_URL from the environment
# (recommended), or set them explicitly here.
provider "enderlane" {}

module "tenant" {
  source  = "enderlane/core/enderlane"
  version = "~> 0.2"

  default_stages = {
    alpha   = { order_index = 0 }
    bravo   = { order_index = 1 }
    charlie = { order_index = 2 }
  }

  lane_groups = {
    acme-platform = {
      lanes = {
        web = { description = "Customer SPA", deployment_type = "SPA" }
        api = { description = "Backend API", deployment_type = "CLOUD_RUN" }
      }
    }
  }
}
```

Runnable configurations are in [`examples/basic`](examples/basic) (one group,
two lanes, default stages) and [`examples/complete`](examples/complete)
(everything: two edge providers, a tenant default edge, per-group stage
overrides, gate chains, a custom preset, unit-kind mappings).

## Consuming a slice

Each of the four submodules wraps its provider resources and can be consumed on
its own:

```hcl
module "group" {
  source = "enderlane/core/enderlane//modules/lane-group"
  # ...
}
```

Available: `//modules/lane-group`, `//modules/edge-config`,
`//modules/gate-chain`, `//modules/field-set-preset`.

## Prerequisites

- **Terraform** >= 1.5
- The **`enderlane` provider** (>= 0.1.0), configured with an Enderlane machine
  API key (via `ENDERLANE_API_KEY`, or the provider's `api_key` argument).

That's it — no shell tooling. (v0.1 drove the API through bash/curl/jq; v0.2
runs entirely on the provider.)

## Inputs (root module)

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `tenant_id` | `string` | `null` | Required only when `default_edge_provider_config` is set (the tenant-default resource needs an explicit tenant id; the API has no current-tenant lookup). |
| `edge_provider_configs` | `map(object)` | `{}` | Edge configs keyed by name. |
| `default_edge_provider_config` | `string` | `null` | Name of the edge config to set as the tenant default. |
| `default_stages` | `map(object)` | `{}` | Tenant-default stage progression, keyed by stage name. |
| `lane_groups` | `map(object)` | `{}` | Lane groups keyed by group name. |
| `gate_chains` | `list(object)` | `[]` | Gate chain configs. |
| `field_set_presets` | `map(object)` | `{}` | Field-set presets keyed by preset name. |
| `unit_kind_field_sets` | `list(object)` | `[]` | Unit-kind → preset mappings. |

Object shapes:

- `edge_provider_configs` value: `{ provider (CLOUDFLARE|CLOUDFRONT),
  cloudflare_account_id?, cloudflare_api_token? (sensitive),
  cloudflare_config_store_ns_id?, cloudfront_region?, aws_access_key_id?,
  aws_secret_access_key? (sensitive) }`.
- `default_stages` / group `stages` value: `{ order_index (number), kv_prefix?,
  description?, requires_approval? }`.
- `lane_groups` value: `{ kv_namespace_id?, edge_provider_config? (name of an
  edge_provider_configs entry), lanes = map(name -> { description?,
  deployment_type? }), stages = map(name -> { order_index, kv_prefix?,
  description?, requires_approval? }) }`. `stages` are per-group overrides.
- `gate_chains` element: `{ scope_kind (tenant|group|lane), scope_group?,
  scope_lane?, is_entry (bool), to_stage?, initiation_mode (MANUAL|AUTO), steps =
  list({ mode (SINGLE|ALL|ANY), conditions = list({ kind
  (APPROVAL|FREEZE|SOAK|DEPENDENCY), subject?, duration_minutes?,
  dependency_lane?, dependency_stage? }) }) }`.
- `field_set_presets` value: `{ description?, fields = list({ name, required
  (bool), description?, allowed_values? }) }` (field order preserved).
- `unit_kind_field_sets` element: `{ kind (BUILD|CONFIG), preset (preset name —
  your own or a seeded system preset), scope_group?, scope_lane? }`.

All cross-references between blocks (a group's `edge_provider_config`, a gate
chain's `scope_group`/`to_stage`/`dependency_lane`, a mapping's `preset`) are by
**name**; the module resolves each to the underlying provider resource's id.

## Outputs

`edge_provider_config_ids`, `lane_group_ids`, `lane_ids` (nested by group),
`group_stage_ids` (nested by group), `default_stage_ids`, `field_set_preset_ids`,
`gate_chain_ids` — each a name → id map.

## Stage scoping

Stages exist at two levels, both driven here:

- **Tenant-default** stages (`default_stages`) — no `lane_group_id`; the shared
  progression every group inherits by default.
- **Group override** stages (a group's `stages`) — created with the group's id,
  so that group gets its own progression instead of the tenant default.

## Notes and limitations

These reflect the current Enderlane v2 API and the provider that wraps it:

- **Declare-only fields.** A lane group's edge wiring (`edge_provider_config`,
  `kv_namespace_id`, and the mirrored provider kind) and a lane's `description`
  are **not read back** by the v2 API, so the provider stores them as declared
  and does not drift-check them against the server.
- **A group-bound edge config cannot be destroyed while its group exists**
  (END-87). Binding a group to an edge config (`edge_provider_config` on the
  group) makes the group hold a foreign key the API cannot clear (an explicit
  null is treated as "unchanged"), and groups only soft-delete — so the API
  refuses to hard-delete an edge config any group still references. The
  `examples/complete` config therefore leaves its group unbound (using the
  tenant default instead) so it destroys cleanly. Either don't bind edge configs
  you intend to tear down, or remove the group out-of-band first.
- **Write-only edge secrets.** `cloudflare_api_token` / `aws_secret_access_key`
  are never returned by the API (only `has_*` presence booleans), so the
  provider stores the declared value in state and cannot detect drift on them.
- **Lane-group-scoped unit-kind mappings have no read path** — the API exposes
  only `effectiveFieldSet(kind, laneId)`, so out-of-band drift on a
  *group-scoped* mapping is not detected (the declared preset is retained).
- **Do not name a preset after a seeded system preset** (`Build`, `Config
  version`) — those are immutable and shared, and are not managed here.

## License

[Apache-2.0](LICENSE). Copyright Enderlane.
