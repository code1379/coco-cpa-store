"""Exercise the actual upgrade script without GitHub requests or Nix builds."""

from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import unittest

import yaml


ROOT = Path(__file__).resolve().parents[1]
WORKFLOW = yaml.safe_load((ROOT / ".github/workflows/sync-upstreams.yml").read_text())
SCRIPT = WORKFLOW["jobs"]["sync-freetier2api"]["steps"][-1]["run"]
FILES = [
    "nix/packages/plugins/default.nix",
    "plugins/freetier2api/go/main.go",
    "plugins/freetier2api/README.md",
    "plugins/freetier2api/plugin.json",
    "plugins/freetier2api/CHANGELOG.md",
    "README.md",
]


class UpgradeScriptTests(unittest.TestCase):
    def test_current_pin_exits_without_rebuilding(self):
        source = (ROOT / FILES[0]).read_text()
        owner, repo, revision = re.search(
            r'owner = "([^"]+)";\s*repo = "([^"]+)";\s*rev = "([^"]+)"',
            source,
        ).groups()
        version = re.search(
            r'pluginVersion\s*=\s*"([^"]+)"', (ROOT / FILES[1]).read_text()
        ).group(1)
        # This includes the real early-exit condition. Falling through would
        # invoke prefetch/build in production and deliberately fails this test.
        start = SCRIPT.index('current_source="$(')
        end = SCRIPT.index('hash="$(nix store prefetch-file', start)
        result = subprocess.run(
            ["bash", "-eu"],
            input=(
                f"repo={owner}/{repo}\nrevision={revision}\n"
                f"version={version}\ntag=v{version}\n"
                + SCRIPT[start:end]
                + "exit 99\n"
            ),
            cwd=ROOT,
            text=True,
            capture_output=True,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn(f"already at v{version}", result.stdout)

    def test_upgrade_updates_metadata_and_is_idempotent(self):
        marker = 'python3 - "$repo" "$revision" "$hash" "$version" <<\'PY\'\n'
        source = SCRIPT.split(marker, 1)[1].split("\nPY", 1)[0]
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name in FILES:
                target = root / name
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(ROOT / name, target)
            args = [
                sys.executable,
                "-",
                "cxy2730/CLIProxyAPI-freetier2api-plugin",
                "a" * 40,
                "sha256-test-source-hash",
                "99.0.0",
            ]
            subprocess.run(args, input=source, cwd=root, text=True, check=True)
            first = {name: (root / name).read_bytes() for name in FILES}
            subprocess.run(args, input=source, cwd=root, text=True, check=True)
            second = {name: (root / name).read_bytes() for name in FILES}
            self.assertEqual(first, second)
            self.assertIn('pluginVersion = "99.0.0"', first[FILES[1]].decode())
            self.assertIn('rev = "' + "a" * 40 + '"', first[FILES[0]].decode())
            self.assertIn('hash = "sha256-test-source-hash"', first[FILES[0]].decode())
            self.assertIn("[v99.0.0]", first[FILES[2]].decode())
            self.assertIn("commit `" + "a" * 40 + "`", first[FILES[2]].decode())
            self.assertEqual(first[FILES[4]].decode().count("## 99.0.0"), 1)


if __name__ == "__main__":
    unittest.main()
