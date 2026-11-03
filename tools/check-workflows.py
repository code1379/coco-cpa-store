"""Validate workflow YAML, shell scripts, and embedded Python/JavaScript syntax."""

import ast
from pathlib import Path
import re
import subprocess
import sys

import yaml


def check_workflow(path):
    workflow = yaml.safe_load(path.read_text())
    for job_id, job in workflow["jobs"].items():
        for step in job.get("steps", []):
            if "run" not in step:
                continue
            script = step["run"]
            label = f"{path}: {job_id}: {step.get('name', 'run')}"
            subprocess.run(["bash", "-n"], input=script, text=True, check=True)
            lines = script.splitlines()
            for index, line in enumerate(lines):
                heredoc = re.search(r"<<['\"]?(PY|NODE)['\"]?\s*$", line)
                if not heredoc:
                    continue
                delimiter = heredoc.group(1)
                end = lines.index(delimiter, index + 1)
                source = "\n".join(lines[index + 1 : end])
                if delimiter == "PY":
                    ast.parse(source, filename=label)
                else:
                    subprocess.run(
                        ["node", "--check"], input=source, text=True, check=True
                    )
    print(f"{path}: workflow scripts passed syntax checks")


if __name__ == "__main__":
    root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(".")
    for path in sorted((root / ".github/workflows").glob("*.yml")):
        check_workflow(path)
