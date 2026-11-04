{
  pkgs,
  flake,
  ...
}:

let
  inherit (pkgs) lib;
  pluginsDir = flake + "/plugins";
  # The local pluginVersion placeholder is the package/ZIP version. For
  # FreeTier2API, postPatch writes that exact version into upstream main.go.
  versionOf =
    id:
    let
      versions = lib.concatMap (
        line:
        let
          version = builtins.match ''[[:space:]]*pluginVersion[[:space:]]*=[[:space:]]*"([^"]*)".*'' line;
        in
        if version == null then [ ] else version
      ) (lib.splitString "\n" (builtins.readFile (pluginsDir + "/${id}/go/main.go")));
    in
    if builtins.length versions == 1 then
      builtins.head versions
    else
      throw "plugins/${id}/go/main.go must declare pluginVersion exactly once";

  entries = builtins.readDir pluginsDir;
  discoveredIds = builtins.filter (
    id:
    (entries.${id} or null) == "directory"
    && builtins.pathExists (pluginsDir + "/${id}/plugin.json")
    && builtins.pathExists (pluginsDir + "/${id}/go/go.mod")
  ) (builtins.attrNames entries);

  metaFor = id: builtins.fromJSON (builtins.readFile (pluginsDir + "/${id}/plugin.json"));

  # The plugin.json id is used in artifact and registry paths; it must match
  # the directory name so per-plugin lookups stay consistent.
  pluginIds =
    if lib.all (id: (metaFor id).id == id) discoveredIds then
      discoveredIds
    else
      throw "plugin.json id must match its directory name under plugins/";

  buildLibrary =
    id:
    pkgs.buildGoModule {
      pname = id;
      version = versionOf id;
      # Rename the source root: the directory is called "go", which would
      # otherwise land on buildGoModule's GOPATH and make Go ignore go.mod.
      src =
        if id == "freetier2api" then
          pkgs.fetchFromGitHub {
            owner = "cxy2730";
            repo = "CLIProxyAPI-freetier2api-plugin";
            rev = "5cee22202bca2f199c1a31ffa2881f06915237a8";
            hash = "sha256-3+By2w1Hmhqqza3Jmh1uEaQWuJfQevMXq61ZfbMZHwI=";
          }
        else
          builtins.path {
            name = id;
            path = pluginsDir + "/${id}/go";
          };

      patches =
        if id == "freetier2api" then
          let
            patchDir = pluginsDir + "/freetier2api/patches";
            patchNames =
              if builtins.pathExists patchDir then
                lib.filter (name: lib.hasSuffix ".patch" name) (builtins.attrNames (builtins.readDir patchDir))
              else
                [ ];
          in
          map (name: patchDir + "/${name}") patchNames
        else
          [ ];
      vendorHash = import (pluginsDir + "/${id}/vendor-hash.nix");
      # Patch context offsets must not leave .orig files in the vendor tree:
      # upstream's architecture tests reject files outside its source allowlist.
      patchFlags = [
        "-p1"
        "--no-backup-if-mismatch"
      ];
      postPatch = lib.optionalString (id == "freetier2api") ''
        # Upstream main.go initializes pluginVersion from app.DefaultVersion.
        # Replace the declaration itself so App.Version() reports our pinned package version.
        substituteInPlace main.go \
          --replace-fail 'var pluginVersion = app.DefaultVersion' 'var pluginVersion = "${versionOf id}"'
      '';

      # Plugins are loaded through the CLIProxyAPI C ABI, so the artifact is a
      # cgo-produced shared library, not a regular binary.
      # Also inherited by the vendoring derivation. Go may write toolchain
      # configuration before tests run, so provide a writable home from build start.
      preBuild = ''
        export HOME="$TMPDIR/plugin-test-home"
        export XDG_CONFIG_HOME="$HOME/.config"
        export XDG_CACHE_HOME="$HOME/.cache"
        mkdir -p "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME"
      '';
      buildPhase = ''
                runHook preBuild
                if [[ "${id}" == "freetier2api" ]]; then
                  # Verify the actual version exposed by the App used by the C ABI.
                  cat > version_injection_check_test.go <<'GO_TEST'
        package main

        import "testing"

        func TestPluginVersionMatchesPackage(t *testing.T) {
            const expected = "${versionOf id}"
            if got := pluginApp.Version(); got != expected {
                t.Fatalf("plugin version = %q, want %q", got, expected)
            }
        }
        GO_TEST
                  go test -run '^TestPluginVersionMatchesPackage$' .
                  rm version_injection_check_test.go
                fi
                go build -trimpath -buildmode=c-shared -o "${id}.so" .
                runHook postBuild
      '';

      doCheck = true;
      # Tests of a plugin's management page script run under node.
      nativeCheckInputs = [ pkgs.nodejs_24 ];
      checkPhase = ''
        runHook preCheck
        # Qoder runtime-info needs host machine identity unavailable in Nix sandbox.
        # The embedded asset extraction test and all other Go tests still run.
        export FREETIER2API_SKIP_EMBEDDED_IDENTITY_EXECUTION=1
        go test ./...
        runHook postCheck
      '';

      installPhase = ''
        runHook preInstall
        install -Dm755 "${id}.so" "$out/${id}.so"
        runHook postInstall
      '';

      meta.platforms = [ "x86_64-linux" ];
    };

  # The store installs <id>-v<version>-<goos>-<goarch>.zip holding
  # <id>-v<version>.so at its root.
  packZip =
    id:
    let
      name = "${id}-v${versionOf id}";
    in
    pkgs.runCommand "${name}-linux-amd64" { nativeBuildInputs = [ pkgs.zip ]; } ''
      # cp -p keeps the store's normalized mtime and zip -X drops extended
      # attributes, so a rerun of a release reproduces the published bytes.
      cp -p "${buildLibrary id}/${id}.so" "${name}.so"
      mkdir -p "$out"
      zip -X -j "$out/${name}-linux-amd64.zip" "${name}.so"
    '';

  zips = lib.genAttrs pluginIds packZip;
in
# Release pipelines build one plugin as .#plugins.<id>; the joined output keeps
# nix flake check building and testing every plugin.
pkgs.symlinkJoin {
  name = "whexy-cpa-store-plugins";
  paths = builtins.attrValues zips;
  passthru = zips;
  meta.platforms = [ "x86_64-linux" ];
}
