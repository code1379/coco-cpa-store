{ pkgs, flake, ... }:

pkgs.runCommand "workflow-checks"
  {
    nativeBuildInputs = [
      pkgs.actionlint
      pkgs.shellcheck
      pkgs.bash
      pkgs.nodejs_24
      (pkgs.python3.withPackages (ps: [ ps.pyyaml ]))
    ];
  }
  ''
    cd ${flake}
    actionlint .github/workflows/*.yml
    python3 tools/check-workflows.py
    python3 tools/test-upstream-sync.py
    touch "$out"
  ''
