# FreeTier 2API patches

Place small, reviewed unified-diff patches here to customize the pinned upstream source without copying the full upstream tree into this repository. The Nix package applies files ending in `.patch` in lexicographic order. Keep each patch focused and add tests alongside it when practical.

Current patches:

- `0001-cline-cloud-model-catalog.patch`: expose the Cline Cloud model category.
- `0002-default-disable-cline-nonfree-models.patch`: default-disable non-free/unknown Cline models while preserving explicit user overrides.
- `0003-nix-sandbox-skip-host-machine-identity-test.patch`: skip only Qoder's host machine-identity process test when the Nix build explicitly sets `FREETIER2API_SKIP_EMBEDDED_IDENTITY_EXECUTION=1`. The embedded runtime asset, extraction test, production identity code, and all other tests remain enabled. The upstream v0.1.47 CI passes the unmodified process test on a normal GitHub runner.
- `0004-preserve-store-management-namespace.patch`: match management routes and the console to the installed `freetier2api` ID while preserving the `freetier` credential provider and state directory. Integration fixtures use the installed namespace, and a regression test checks the console response and API prefix.
- `0005-zcode-marketing-fallback-for-held-plans.patch`: query marketing when billing offers contain no unheld plan; preserve the fallback error when no claimable offer can be confirmed.
