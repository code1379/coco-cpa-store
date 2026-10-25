# CLIProxyAPI Playground

Personal-use Playground plugin for CLIProxyAPI.

## Features

- Tailwind CSS utility classes for a responsive UI (loaded from Tailwind Play CDN).
- Chat Completions testing with optional streaming, system prompt, temperature and max tokens.
- Image generation testing via `POST /v1/images/generations`.
- Dynamic model list via `GET /v1/models`. When the Model Groups plugin is installed and enabled, configured group IDs appear in this same list and can be selected directly.
- Attempts to reuse a client API key from the logged-in management configuration; a client key can also be entered manually.
- Shows latency, returned model, usage where available, and upstream errors.

## Important notes

- Model groups must be enabled and configured in the Model Groups plugin first. The Playground does not create groups; it lists whatever the server exposes from `/v1/models`.
- Image generation works only if the selected upstream/model supports CLIProxyAPI's `/v1/images/generations` endpoint. It may consume quota or incur cost.
- Tailwind Play CDN requires browser access to `cdn.tailwindcss.com`. The Playground's own logic and HTML are embedded in the Go plugin; if you need a fully offline UI, replace the CDN with a committed compiled Tailwind stylesheet in a later step.
- API keys are kept in page memory except for management credentials already stored by the management UI. Avoid using this page on untrusted devices.

## Build

This plugin is built by the repository's Nix flake and GitHub Actions CI. No public plugin-store release is performed.
