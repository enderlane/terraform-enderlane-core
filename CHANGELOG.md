# Changelog

## v0.2.0 — built on the `enderlane` provider

Complete re-implementation on top of the official
[`enderlane`](https://registry.terraform.io/providers/enderlane/enderlane)
Terraform provider (>= 0.1.0). Every entity is now a first-class provider
resource with real plan/apply/**drift and convergence** semantics. The entire
v0.1 mechanism — `null_resource` + `local-exec` shell scripts + `external` data
sources driving the GraphQL API via bash/curl/jq — is gone.

### Breaking changes

- **`api_url` / `api_key` variables removed.** Configure the provider in your
  root instead:

  ```hcl
  terraform {
    required_providers {
      enderlane = { source = "enderlane/enderlane", version = ">= 0.1.0" }
    }
  }
  provider "enderlane" {}   # reads ENDERLANE_API_KEY / ENDERLANE_API_URL
  ```

  The module inherits the default `enderlane` provider; it declares
  `required_providers` but takes no api_url/api_key of its own. The API key is
  no longer written into this module's state by the module (it lives with the
  provider), though provider state handling still applies — keep state
  encrypted.

- **`tenant_id` variable added.** Required only when
  `default_edge_provider_config` is set: the provider's tenant-default resource
  needs an explicit tenant id and the v2 API exposes no current-tenant lookup.
  v0.1 discovered the tenant id automatically; v0.2 cannot, so you must supply
  it.

- **Prerequisites shrank.** No more bash / curl / jq on the runner — just
  Terraform >= 1.5 and the `enderlane` provider.

### Unchanged (by design)

- The variable schema for `edge_provider_configs`, `default_stages`,
  `lane_groups` (with nested `lanes` / `stages`), `gate_chains`,
  `field_set_presets`, and `unit_kind_field_sets` — same shapes, same
  name-keyed maps.
- **Name-based cross-references** everywhere (a group's `edge_provider_config`,
  a gate chain's `scope_group` / `to_stage` / `dependency_lane`, a mapping's
  `preset`). Where v0.1 resolved these via jq at run time, v0.2 resolves them to
  provider resource ids internally — the caller still writes names.
- The four registry-indexed submodules (`lane-group`, `edge-config`,
  `gate-chain`, `field-set-preset`) keep their purpose.
- Outputs (`*_ids` name → id maps).

### Additive

- `requires_approval` on stages (tenant-default and group-override), surfaced
  from the provider's stage resource.

### Still true (documented in the README)

- Declare-only lane-group edge wiring + lane `description` (not read back).
- A group-bound edge config cannot be destroyed while its group exists (END-87).
- Write-only edge secrets (only `has_*` presence booleans are read back).

## v0.1.0

Initial release. Drove the Enderlane v2 GraphQL API through `null_resource` +
`local-exec` bash/curl/jq scripts and `external` data sources (no provider).
