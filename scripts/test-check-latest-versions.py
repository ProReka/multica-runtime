#!/usr/bin/env python3
"""Self-check for check-latest-versions script."""
from pathlib import Path
import sys

# Import functions from check-latest-versions
sys.path.insert(0, str(Path(__file__).parent))
from importlib.machinery import SourceFileLoader
mod = SourceFileLoader("check_latest_versions", str(Path(__file__).parent / "check-latest-versions.py")).load_module()

content = """# comment
NODE_VERSION=26.13.0
MULTICA_CLI_VERSION=0.7.2
CLAUDE_CODE_VERSION=2.1.314
"""

parsed = mod.parse_versions_env(content)
assert parsed["NODE_VERSION"] == "26.13.0"
assert parsed["MULTICA_CLI_VERSION"] == "0.7.2"
assert parsed["CLAUDE_CODE_VERSION"] == "2.1.314"

updated = mod.update_versions_content(content, {"MULTICA_CLI_VERSION": "0.8.0"})
assert "MULTICA_CLI_VERSION=0.8.0" in updated
assert "MULTICA_CLI_VERSION=0.7.2" not in updated
assert "NODE_VERSION=26.13.0" in updated
assert updated.startswith("# comment\n")

print("check-latest-versions tests passed.")
