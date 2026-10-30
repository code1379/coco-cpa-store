# FreeTier 2API (pinned upstream build)

This package builds the upstream [CLIProxyAPI-freetier2api-plugin](https://github.com/jiandanc/CLIProxyAPI-freetier2api-plugin) at pinned commit `ddee2d93c74386256cd8b2ca6e6474dc01d81b34` using this repository's Nix build pipeline.

The upstream project is MIT licensed. Its README restricts use to personal learning and technical research and prohibits commercial sale, API resale, paid hosting, automated reward farming, and public shared pools. Keep those limits in mind and follow each upstream provider's terms.

The upstream source is fetched at build time rather than copied into this directory. Future customizations should be maintained as explicit patch files and applied by Nix, so upstream attribution and the pinned source remain clear.

## Local Cline model policy

The local patch set extends the pinned Cline model parser to include the `clineCloud` category. The model catalogue labels free models explicitly; subscription, Cline Cloud, and unknown Cline models are disabled by default. The existing model-management toggle can explicitly enable a non-free model, and that override is persisted across plugin restarts. An explicit `disabled_models` configuration remains authoritative.

The upstream adapter already includes bounded HTTP timeouts, structured upstream failure classification, a bundled model fallback, and a persistent model-catalog cache that preserves the last successful list when a refresh fails. The local changes build on those mechanisms rather than adding a second retry loop that might replay a partially streamed request.
