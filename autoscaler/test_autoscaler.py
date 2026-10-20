#!/usr/bin/env python3
"""Unit tests for the autoscaler's pure decision logic.

Run with:

    python3 -m unittest discover -s autoscaler -p 'test_*.py' -v

These deliberately avoid Multica, AWS and Docker: the parts that touch live
infrastructure are thin adapters around the functions tested here.
"""

from __future__ import annotations

import json
import os
import tempfile
import unittest
from pathlib import Path

import autoscaler as a


class WantedReplicasTests(unittest.TestCase):
    def test_any_pending_task_wakes_one_runtime(self) -> None:
        self.assertEqual(a.wanted_replicas(1), 1)
        self.assertEqual(a.wanted_replicas(7), 1)

    def test_no_pending_task_sleeps(self) -> None:
        self.assertEqual(a.wanted_replicas(0), 0)


class ScaleDownGuardTests(unittest.TestCase):
    def call(self, **overrides):
        values = {
            "now": 1_000.0,
            "last_scaledown": 0.0,
            "zero_since": 500.0,
            "running": False,
            "cooldown": 300,
            "grace": 120,
        }
        values.update(overrides)
        return a.scale_down_blocked(**values)

    def test_allows_when_every_guard_is_clear(self) -> None:
        self.assertIsNone(self.call())

    def test_cooldown_wins(self) -> None:
        reason = self.call(last_scaledown=900.0)
        self.assertIsNotNone(reason)
        self.assertIn("cooldown", reason or "")

    def test_grace_wins(self) -> None:
        reason = self.call(zero_since=950.0)
        self.assertIsNotNone(reason)
        self.assertIn("grace", reason or "")

    def test_missing_zero_timestamp_holds(self) -> None:
        reason = self.call(zero_since=None)
        self.assertEqual(reason, "grace clock not started")

    def test_running_task_wins(self) -> None:
        self.assertEqual(self.call(running=True), "task still running")

    def test_zero_grace_is_allowed(self) -> None:
        self.assertIsNone(self.call(zero_since=1_000.0, grace=0))


class LoadRuntimesTests(unittest.TestCase):
    def test_parses_inline_json(self) -> None:
        roles = a.load_runtimes(
            '[{"daemon_id":"multica-php","service":"multica-php"}]'
        )
        self.assertEqual(len(roles or []), 1)
        self.assertEqual(roles[0].daemon_id, "multica-php")  # type: ignore[index]

    def test_parses_a_file(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "roles.json"
            path.write_text(
                json.dumps([{"daemon_id": "a", "service": "svc-a"}]),
                encoding="utf-8",
            )
            roles = a.load_runtimes(str(path))
        self.assertEqual(roles, [a.Role("a", "svc-a")])

    def test_unset_means_legacy_mode(self) -> None:
        self.assertIsNone(a.load_runtimes(None))
        self.assertIsNone(a.load_runtimes(""))

    def test_rejects_empty_array(self) -> None:
        with self.assertRaises(ValueError):
            a.load_runtimes("[]")

    def test_rejects_missing_fields(self) -> None:
        with self.assertRaises(ValueError):
            a.load_runtimes('[{"daemon_id":"a"}]')

    def test_rejects_duplicates(self) -> None:
        with self.assertRaises(ValueError):
            a.load_runtimes(
                '[{"daemon_id":"a","service":"x"},{"daemon_id":"a","service":"y"}]'
            )

    def test_rejects_duplicate_services(self) -> None:
        with self.assertRaises(ValueError):
            a.load_runtimes(
                '[{"daemon_id":"a","service":"x"},{"daemon_id":"b","service":"x"}]'
            )

    def test_rejects_bad_json(self) -> None:
        with self.assertRaises(ValueError):
            a.load_runtimes("{not json")


class AsListTests(unittest.TestCase):
    def test_accepts_bare_list(self) -> None:
        self.assertEqual(a.as_list([{"id": 1}], "agents"), [{"id": 1}])

    def test_unwraps_envelope(self) -> None:
        self.assertEqual(a.as_list({"agents": [{"id": 1}]}, "agents"), [{"id": 1}])

    def test_ignores_non_dict_items(self) -> None:
        self.assertEqual(a.as_list({"agents": [{"id": 1}, "x", None]}, "agents"), [{"id": 1}])

    def test_unknown_shape_is_empty(self) -> None:
        self.assertEqual(a.as_list({"nope": 1}, "agents"), [])
        self.assertEqual(a.as_list(None, "agents"), [])


class LegacyDesiredTests(unittest.TestCase):
    def setUp(self) -> None:
        self._saved = {k: os.environ.get(k) for k in (
            "AUTOSCALER_TASKS_PER_WORKER",
            "AUTOSCALER_MIN_WORKERS",
            "AUTOSCALER_MAX_WORKERS",
        )}

    def tearDown(self) -> None:
        for key, value in self._saved.items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value

    def test_zero_pending_scales_to_zero(self) -> None:
        self.assertEqual(a.legacy_desired(0), 0)

    def test_ceil_division(self) -> None:
        os.environ["AUTOSCALER_TASKS_PER_WORKER"] = "2"
        self.assertEqual(a.legacy_desired(5), 3)

    def test_clamped_to_max(self) -> None:
        os.environ["AUTOSCALER_TASKS_PER_WORKER"] = "1"
        os.environ["AUTOSCALER_MAX_WORKERS"] = "2"
        self.assertEqual(a.legacy_desired(9), 2)

    def test_minimum_is_respected(self) -> None:
        os.environ["AUTOSCALER_MIN_WORKERS"] = "2"
        self.assertEqual(a.legacy_desired(0), 2)


if __name__ == "__main__":
    unittest.main()
