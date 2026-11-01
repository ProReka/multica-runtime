#!/usr/bin/env python3
"""No Docker, credentials, or network required."""
import importlib.util
from datetime import datetime, timezone
from pathlib import Path

spec = importlib.util.spec_from_file_location("check_runtime", Path(__file__).with_name("check-runtime.py"))
check = importlib.util.module_from_spec(spec)
spec.loader.exec_module(check)
now = datetime(2026, 11, 1, 12, tzinfo=timezone.utc)
runtime = {"status": "online", "last_seen_at": "2026-11-01T11:59:30Z"}
active = [{"id": "a", "status": "running", "started_at": "2026-11-01T10:00:00Z"}]
queued = [{"id": "q", "status": "queued"}]
messages = {"a": [{"created_at": "2026-11-01T11:59:40Z"}]}
lines, bad = check.diagnose({"max_concurrent_tasks": 1}, runtime, active + queued, messages, now, 600)
assert not bad and any(s.startswith("SATURATED:") for s in lines)
assert any(s.startswith("ACTIVITY:") for s in lines), "Recent events are not proof of useful progress"
_, bad = check.diagnose({"max_concurrent_tasks": 2}, runtime, active + queued, messages, now, 600)
assert bad, "Free slots with queued work need investigation"
_, bad = check.diagnose({}, None, [], {}, now, 600)
assert bad, "Missing bound runtime must not appear healthy"
lines, bad = check.diagnose({}, runtime, active, {"a": []}, now, 600)
assert bad and any(s.startswith("CHECK:") for s in lines)
lines, bad = check.diagnose({}, runtime, active, {"a": []}, now, 600)
assert bad and any("zero messages" in s for s in lines)
timeout_event = {"created_at": "2026-11-01T11:59:59Z", "type": "tool_result",
                 "output": "(no output)\nshell tool terminated command after exceeding timeout 300000 ms"}
lines, bad = check.diagnose({}, runtime, active, {"a": [timeout_event]}, now, 600)
assert bad and any(s.startswith("STALLED:") for s in lines), "Fresh timeout is not progress"
error_event = {"created_at": "2026-11-01T11:59:59Z", "type": "error",
               "content": "Cannot connect to API"}
lines, bad = check.diagnose({}, runtime, active, {"a": [error_event]}, now, 600)
assert bad and any(s.startswith("FAILED:") for s in lines), "Running status cannot hide API errors"
print("Runtime diagnosis checks passed.")
