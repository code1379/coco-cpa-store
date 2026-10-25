# Coco CPA Store

个人使用的 CLIProxyAPI 插件开发仓库，基于 [Whexy 的 whexy-cpa-store](https://github.com/whexy/whexy-cpa-store) 进行维护。

本仓库当前目标是**开发、测试和构建插件**，不是公开插件商城。GitHub Actions 只运行验证和构建，并把 ZIP 作为短期 workflow artifact 保存；不会自动创建 GitHub Release、打 tag 或更新插件商店注册表。

## 插件包

保留的上游插件，分别维护在独立目录：

- `client-keys` — 按 CLIProxyAPI 客户端 API Key 设置模型可见性、使用权限和 Responses API 权限。
- `extra-models` — 为内置提供商的模型目录补充模型 ID。
- `model-groups` — 将一个模型 ID 映射到多个候选模型，并支持轮询、加权轮询和 fill-first 路由。
- `opencode-go` — 将 OpenCode Go 模型接入 CLIProxyAPI，并提供模型启停、OAuth/Key 管理和额度展示。
- `system-prompt` — 按模型 ID 或匹配规则追加系统提示词。
- `usage-dashboard` — 展示 Token、估算费用和会话统计。

我们自己的插件：

- `cline-provider` — 计划中的 Cline Provider，动态发现模型，默认启用免费模型、默认禁用订阅/付费模型，并在服务端执行启停限制。
- `cli-playground` — 将已有 Playground 整理成独立的 CLIProxyAPI 原生插件。

## 目录约定

每个插件独立维护在 `plugins/<id>/` 下，保留上游约定：

```text
plugins/<id>/
  plugin.json
  vendor-hash.nix
  CHANGELOG.md
  go/
    go.mod
    main.go
```

Go 插件使用 CLIProxyAPI 的 C ABI 插件接口，并通过 `-buildmode=c-shared` 构建动态库。Nix 定义各插件的构建和测试方式。

## GitHub Actions

工作流位于 `.github/workflows/ci.yml`，在 push、pull request 和手动触发时运行：

1. 安装 Nix。
2. 运行 `nix flake check --print-build-logs`，检查格式、元数据、测试和插件构建。
3. 为每个可构建插件生成 ZIP。
4. 上传为 GitHub Actions artifact，保留 14 天。

工作流**不会**创建 tag、GitHub Release、更新 `registry.json` 或发布插件商店。

## 本地验证

需要安装 Nix，并在仓库根目录运行：

```bash
nix flake check --print-build-logs
nix build .#plugins.opencode-go --print-build-logs
```

GitHub Actions 产物可以在对应 workflow run 的 Artifacts 区域下载。下载后先在测试环境验证，不要直接覆盖服务器正在运行的插件。

## 上游来源与许可

- 上游仓库：[whexy/whexy-cpa-store](https://github.com/whexy/whexy-cpa-store)
- 上游各插件的 `plugin.json` 声明了 MIT，但上游根目录当前未找到统一的 `LICENSE` 文件。公开分发前应核实各插件源码和依赖的实际授权，并保留原作者版权声明。
- Cline Provider 的实现可参考 [chengyixu/cpa-plugin-cline](https://github.com/chengyixu/cpa-plugin-cline)，该仓库包含自己的 MIT LICENSE；借鉴或复制代码时仍需保留对应许可声明。

## 安全说明

- 不要提交 API Key、OAuth token、认证 JSON、私钥或服务器配置。
- Cline 免费模型的 `x-client-type: cline-cli` 是客户端标识，不是认证凭证；当前可用性是基于实测，服务端策略可能变化。
- 本仓库仅构建测试，不自动发布任何插件，也不修改 1Panel 服务器。
