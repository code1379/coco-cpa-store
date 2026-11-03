{
  pkgs,
  flake,
  ...
}:

let
  inherit (pkgs) lib;
  pluginsDir = flake + "/plugins";
  # The local placeholder carries the pinned upstream release version. It drives
  # both the package/ZIP version and the version injected into the running plugin.
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
            rev = "f60ab60cb9cad0a0485bda8c4a8087b5859bc099";
            hash = "sha256-z0hdJ5T9ZE9bLR2WfE+9epyUdmIB+pRFDOEa5WgpSyY=";
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

      # Plugins are loaded through the CLIProxyAPI C ABI, so the artifact is a
      # cgo-produced shared library, not a regular binary.
      buildPhase = ''
        runHook preBuild
        if [[ "${id}" == "freetier2api" ]]; then
          # Inject the version into the Go variable used by pluginApp.Version().
          # This changes the runtime-reported version, not only the ZIP filename.
          go build -trimpath -buildmode=c-shared -ldflags "-X main.pluginVersion=${versionOf id}" -o "${id}.so" .
        else
          go build -trimpath -buildmode=c-shared -o "${id}.so" .
        fi
        if [[ "${id}" == "freetier2api" ]]; then
          go version -m "${id}.so" | grep -F -- "main.pluginVersion=${versionOf id}" >/dev/null || {
            echo "Compiled FreeTier2API runtime version does not match ${versionOf id}" >&2
            exit 1
          }
        fi
        runHook postBuild
      '';

      doCheck = true;
      # Tests of a plugin's management page script run under node.
      nativeCheckInputs = [ pkgs.nodejs_24 ];
      checkPhase = ''
        runHook preCheck
        # Nix builds commonly set HOME to /homeless-shelter, which is not writable.
        # Some integration tests exercise plugin state persistence under the user's home.
        export HOME="$TMPDIR/plugin-test-home"
        mkdir -p "$HOME"
        export XDG_CONFIG_HOME="$HOME/.config"
        export XDG_CACHE_HOME="$HOME/.cache"
        mkdir -p "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME"
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
