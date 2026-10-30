#!/usr/bin/env python3
"""Run with python3 scripts/test-ci-plan.py; no Docker required."""

import importlib.util
from pathlib import Path
import unittest


spec = importlib.util.spec_from_file_location("ci_plan", Path(__file__).with_name("ci-plan.py"))
ci = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ci)


class PlanTests(unittest.TestCase):
    ARGS = {
        "base": {"NODE_VERSION"},
        "python": {"UV_VERSION"},
        "devops": {"UV_VERSION"},
        "node": {"PLAYWRIGHT_VERSION"},
        "qa": {"PLAYWRIGHT_VERSION"},
        "design": {"PLAYWRIGHT_VERSION"},
    }

    def selected(self, paths=(), keys=(), **kwargs):
        result = ci.plan(paths, keys, self.ARGS, **kwargs)
        names = {row["variant"] for row in result["matrix"]["include"]}
        self.assertNotIn("base", names)
        if result["base"]:
            names.add("base")
        self.assertEqual(result["publish"], bool(names))
        return names

    def test_docs_and_tests_only(self):
        self.assertEqual(self.selected(["docs/ci.md", "README.md", "scripts/test-worktrees.sh"]), set())

    def test_base_propagates(self):
        self.assertEqual(self.selected(["images/base/lib/config.sh"]), ci.ALL)
        self.assertEqual(self.selected(keys=["NODE_VERSION"]), ci.ALL)

    def test_pr_tests_direct_variants_with_changed_base(self):
        result = ci.plan(["images/base/Dockerfile", "images/php/Dockerfile"], [], self.ARGS)
        self.assertEqual(result["pr_variants"], ["php"])
        self.assertEqual(len(result["matrix"]["include"]), len(ci.VARIANTS))
        self.assertEqual(ci.plan(["images/base/Dockerfile"], [], self.ARGS)["pr_variants"], [])

    def test_variant_only(self):
        self.assertEqual(self.selected(["images/php/Dockerfile"]), {"php"})

    def test_shared_versions(self):
        self.assertEqual(self.selected(keys=["UV_VERSION"]), {"python", "devops"})
        self.assertEqual(self.selected(keys=["PLAYWRIGHT_VERSION"]), {"node", "qa", "design"})

    def test_autoscaler_only(self):
        self.assertEqual(self.selected(["autoscaler/test_autoscaler.py"]), {"autoscaler"})

    def test_shared_scripts(self):
        for path in ci.SHARED:
            with self.subTest(path=path):
                self.assertEqual(self.selected([path]), ci.ALL)

    def test_unknown_version_and_missing_before(self):
        self.assertEqual(self.selected(keys=["NEW_VERSION"]), ci.ALL)
        self.assertEqual(self.selected(full=True), ci.ALL)

    def test_explicit_selection(self):
        self.assertEqual(self.selected(["images/base/Dockerfile"], variants="node,qa"), {"node", "qa"})
        self.assertEqual(self.selected(variants="base"), {"base"})
        self.assertEqual(self.selected(variants="all"), ci.ALL)
        for value in ("", "unknown", "node,", "auto,node"):
            with self.subTest(value=value), self.assertRaises(ValueError):
                self.selected(variants=value)

    def test_platforms(self):
        rows = ci.plan([], [], {}, "all")["matrix"]["include"]
        self.assertEqual([row["variant"] for row in rows], list(ci.VARIANTS))
        for row in rows:
            self.assertEqual(row["platforms"], "linux/amd64" if row["variant"] == "flutter"
                             else "linux/amd64,linux/arm64")

    def test_version_values_not_comments(self):
        self.assertEqual(ci.versions("# old\nUV_VERSION=1\n"), ci.versions("# new\n\nUV_VERSION=1\n"))


if __name__ == "__main__":
    unittest.main()
