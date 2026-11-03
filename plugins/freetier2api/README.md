# FreeTier 2API (pinned upstream build)

This package builds the maintained upstream [CLIProxyAPI-freetier2api-plugin](https://github.com/cxy2730/CLIProxyAPI-freetier2api-plugin) at release [v0.1.47](https://github.com/cxy2730/CLIProxyAPI-freetier2api-plugin/releases/tag/v0.1.47), pinned to commit `f60ab60cb9cad0a0485bda8c4a8087b5859bc099`.

The repository was originally created by jiandanc and has been maintained independently by cxy2730 since v0.1.29. The upstream project is MIT licensed. Its README restricts use to personal learning and technical research and prohibits commercial sale, API resale, paid hosting, automated reward farming, and public shared pools. Follow the upstream license and each provider's terms.

The upstream source is fetched at build time rather than copied into this repository. We keep only our customizations as reviewed patch files under `patches/`; Nix applies every `.patch` file in lexicographic order.

## Local patches

- `0001-cline-cloud-model-catalog.patch`: include the Cline Cloud model category in the model catalogue.
- `0002-default-disable-cline-nonfree-models.patch`: default-disable subscription, Cline Cloud, and unknown Cline models while preserving the explicit model-management enable override. An explicit `disabled_models` configuration remains authoritative.
- `0003-nix-sandbox-skip-host-machine-identity-test.patch`: skips only the Qoder embedded runtime's host-identity execution test inside the isolated Nix test phase. It does not alter the embedded executable or production identity generation. The asset extraction test and the upstream CI's normal-host identity test remain intact.
- `0004-preserve-store-management-namespace.patch`: keep management routes and the console under the installed `freetier2api` ID. The `freetier` credential provider and state directory stay compatible with existing accounts.

These patches are intentionally separate from upstream source. When upstream changes, CI verifies that all patches still apply and that the resulting Go tests pass. If upstream changes the affected code, update only the relevant patch and its tests.

## Versioning and build

`go/main.go` in this directory is Nix package metadata, not a copied implementation. Nix reads its `pluginVersion` value for the package and ZIP version.

Versions ending in `-store.N` identify local package fixes on top of the pinned upstream release. The runtime reports the full package version, including this suffix.

For FreeTier2API, the Nix `postPatch` phase replaces the upstream declaration `var pluginVersion = app.DefaultVersion` with the exact pinned package version before compilation. This is deliberately a source-level replacement rather than `-ldflags -X`: the upstream module path is `freetier2api-plugin`, so the earlier `-X main.pluginVersion` target did not address the real Go linker symbol.

Before building the shared library, CI runs a temporary Go test that asserts `pluginApp.Version()` returns the pinned package version. The same patched source is then compiled into the final `.so`, so the ZIP filename and runtime-reported version share one source of truth.

The source commit and Nix source hash are pinned in `nix/packages/plugins/default.nix`. The scheduled sync workflow updates those values from the latest upstream formal release and opens an upgrade PR; it does not auto-merge or deploy.
