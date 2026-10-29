{
  pkgs,
  flake,
  ...
}:

let
  inherit (pkgs) lib;
  pluginsDir = flake + "/plugins";
  # Artifacts carry the version the plugin reports to the host: the
  # pluginVersion constant in go/main.go, 0.0.0 until its first release.
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
            owner = "jiandanc";
            repo = "CLIProxyAPI-freetier2api-plugin";
            rev = "e90609d0138c0cfd7f1e00c0f8c827f8e5c22d11";
            hash = "sha256-1sjaNXdr0Vop3Tty/gdCvmY2MLtOz97sJ1OuljmS4c4=";
          }
        else
          builtins.path {
            name = id;
            path = pluginsDir + "/${id}/go";
          };

      postPatch = lib.optionalString (id == "freetier2api") ''
        substituteInPlace main.go \
          --replace-fail 'var pluginVersion = app.DefaultVersion' 'var pluginVersion = "${versionOf id}"'
      '';
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
        go build -trimpath -buildmode=c-shared -o "${id}.so" .
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
