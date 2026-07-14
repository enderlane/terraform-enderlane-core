# terraform-enderlane-core

Declare an entire [Enderlane](https://app.enderlane.com) tenant's configuration
as code — so a team can stand up (and version) its whole delivery setup without
clicking through the UI.

Enderlane moves the things you ship — builds, configuration versions, anything
versioned — through stages you define, safely. This module provisions, in one
declarative block:

- **Edge provider configs** — Cloudflare KV / AWS CloudFront KVS credentials a
  transition writes its live pointer to.
- **Lane groups** — a family of things shipped together — each with its
  **lanes** (deployable apps/components) and, optionally, a per-group **stage**
  override progression.
- **Tenant-default stages** — the shared ordered progression (e.g. `alpha →
  bravo → charlie`) that any group without its own override inherits.
- **Gate chain configs** — ordered gate steps (approval / freeze / soak /
  dependency) attached to a transition, tenant-wide or per group/lane.
- **Field-set presets** — templates describing what details a unit carries —
  plus **unit-kind → preset mappings** choosing which preset validates a unit
  kind, at tenant / group / lane scope.

> **Vocabulary.** A *lane group* holds things that ship together; a *lane* is
> one deployable thing; *stages* are the ordered steps a *unit* (the named,
> versioned thing that moves — a build, a config version) progresses through.
> This module speaks Enderlane's GraphQL v2 vocabulary throughout.

## Quick start

```hcl
module "tenant" {
  source  = "enderlane/core/enderlane"
  version = "~> 0.1"

  api_key = var.enderlane_api_key # sensitive; pass via TF_VAR_enderlane_api_key

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

The root module composes registry-indexed submodules; you can consume one
directly instead of the whole tenant:

```hcl
module "group" {
  source = "enderlane/core/enderlane//modules/lane-group"
  # ...
}
```

Available: `//modules/lane-group`, `//modules/edge-config`,
`//modules/gate-chain`, `//modules/field-set-preset`.

## Prerequisites

The v0 module drives the Enderlane GraphQL API from shell helpers, so the
machine running `terraform apply`/`destroy` (workstation or CI runner) needs:

- **Terraform** >= 1.5
- **bash**, **curl**, and **[jq](https://jqlang.github.io/jq/)** on `PATH`
- Network reach to your Enderlane GraphQL endpoint
- An Enderlane **machine API key** able to manage groups/edge configs/etc.

## Inputs (root module)

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `api_url` | `string` | `https://app.enderlane.com/graphql` | GraphQL v2 endpoint (full path). |
| `api_key` | `string` (sensitive) | — | Machine key, sent as `X-API-Key`. Stored in state — see security note. |
| `edge_provider_configs` | `map(object)` | `{}` | Edge configs keyed by name (see below). |
| `default_edge_provider_config` | `string` | `null` | Name of the edge config to set as the tenant default. |
| `default_stages` | `map(object)` | `{}` | Tenant-default stage progression, keyed by stage name. |
| `lane_groups` | `map(object)` | `{}` | Lane groups keyed by group name (see below). |
| `gate_chains` | `list(object)` | `[]` | Gate chain configs (see below). |
| `field_set_presets` | `map(object)` | `{}` | Field-set presets keyed by preset name. |
| `unit_kind_field_sets` | `list(object)` | `[]` | Unit-kind → preset mappings. |

`edge_provider_configs` value: `{ provider (CLOUDFLARE|CLOUDFRONT),
cloudflare_account_id?, cloudflare_api_token? (sensitive),
cloudflare_config_store_ns_id?, cloudfront_region?, aws_access_key_id?,
aws_secret_access_key? (sensitive) }`.

`default_stages` / group `stages` value: `{ order_index (number), kv_prefix?,
description? }`.

`lane_groups` value: `{ kv_namespace_id?, edge_provider_config? (name of an
edge_provider_configs entry), lanes = map(name -> { description?,
deployment_type? }), stages = map(name -> { order_index, kv_prefix?,
description? }) }`. `stages` are per-group overrides of the tenant default.

`gate_chains` element: `{ scope_kind (tenant|group|lane), scope_group?,
scope_lane?, is_entry (bool), to_stage?, initiation_mode (MANUAL|AUTO), steps =
list({ mode (SINGLE|ALL|ANY), conditions = list({ kind
(APPROVAL|FREEZE|SOAK|DEPENDENCY), subject?, duration_minutes?,
dependency_lane?, dependency_stage? }) }) }`.

`field_set_presets` value: `{ description?, fields = list({ name, required
(bool), description?, allowed_values? }) }`. Field order is preserved.

`unit_kind_field_sets` element: `{ kind (BUILD|CONFIG), preset (preset name),
scope_group?, scope_lane? }`. Omit both scopes for tenant-wide.

All cross-references between blocks (a group's `edge_provider_config`, a gate
chain's `scope_group`/`to_stage`/`dependency_lane`, a mapping's `preset`) are by
**name**; the module resolves names to ids internally.

## Outputs

`edge_provider_config_ids`, `lane_group_ids`, `lane_ids` (nested by group),
`group_stage_ids` (nested by group), `default_stage_ids`, `field_set_preset_ids`,
`gate_chain_ids` — each a name → id map.

## Stage scoping

Stages exist at two levels, and this module drives both:

- **Tenant-default** stages (`default_stages`) — created unscoped; the shared
  progression every group inherits by default.
- **Group override** stages (a group's `stages`) — created scoped to their lane
  group, so that group gets its own progression instead of the tenant default.

## Unit-kind field-set mapping

Choosing which preset validates a unit kind **is** API-configurable (via
`configureUnitKindFieldSet` / `clearUnitKindFieldSet`), so the module manages it
fully — at tenant, lane-group, or lane scope, resolved most-specific-wins. A
mapping's `preset` may name one of your `field_set_presets` or a seeded system
preset (`Build` / `Config version`).

## How it works / roadmap

**v0 has no custom Terraform provider.** Each entity is a `null_resource` whose
`local-exec` provisioner calls a script in [`scripts/`](scripts) (bash + curl +
jq) to create it, with a `when = destroy` provisioner that deletes it; ids are
read back with `external` data sources. **Idempotency is by name** — the v2 API
has no by-name lookup, so each script lists entities and filters by name,
adopting an existing match instead of recreating it. Re-applying an unchanged
configuration makes no changes.

A native **`terraform-provider-enderlane`** is on the roadmap and will supersede
this shell mechanism; the module's input/output interface is intended to stay
stable across that transition.

## Security: secrets and state

- **The `api_key` is written to Terraform state.** Destroy-time provisioners can
  only read their resource's `triggers`, so the key must live there. Treat your
  state as a secret (encrypted remote backend).
- **Edge provider secrets** (`cloudflare_api_token`, `aws_secret_access_key`)
  are write-only in the API — never read back, so **Terraform cannot detect
  secret drift**. The edge-config submodule tracks a hash of the secrets, so
  **changing a secret value re-sends it on the next apply** — as an in-place
  update (same config id), not a delete-and-recreate, so rotating a secret never
  disturbs a config that is referenced as a group's binding or the tenant
  default. The plaintext reaches the script via the environment only (never a
  command line, never logged) and is **not** stored in state — only the hash is.

## Known limitations (v0)

- **Out-of-band drift is not auto-corrected.** A `null_resource` re-runs its
  create only when a `triggers` value changes; if an entity is deleted directly
  in Enderlane, a re-apply will not recreate it (the output id just reads empty).
  Change an input or `terraform apply -replace=...` to force recreation.
- **A lane-group-bound edge config cannot be destroyed while its group exists.**
  Lane groups soft-delete (their row and its foreign key to the edge config
  survive), while edge configs *hard*-delete and the API refuses to remove one
  still referenced by any group. So `terraform destroy` will refuse (with a
  clear error) for an edge config named as a group's `edge_provider_config`.
  Either don't bind edge configs you intend to tear down, or remove the group's
  row out-of-band first. Unbound edge configs (and the tenant default, which is
  unset before deletion) destroy cleanly.
- **Delete semantics vary by entity** (this mirrors the backend): lane groups,
  lanes, stages, field-set presets, and gate chains **soft**-delete (restorable;
  history retained); edge provider configs **hard**-delete; unit-kind mappings
  and the tenant default edge are **cleared**.
- **Do not name a preset after a seeded system preset** (`Build`, `Config
  version`) — those are immutable and shared, and the module never manages them.

## License

[Apache-2.0](LICENSE). Copyright Enderlane.
