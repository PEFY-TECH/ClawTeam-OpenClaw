#!/usr/bin/env bash
set -euo pipefail

log() { printf '[PEFY-QUAL] %s\n' "$*"; }
fail() { printf '[PEFY-QUAL][FAIL] %s\n' "$*" >&2; exit 1; }

log "Checking Python runtime"
command -v python3 >/dev/null 2>&1 || fail "python3 is required"
python3 - <<'PY'
import sys
if sys.version_info < (3, 10):
    raise SystemExit("Python 3.10+ is required")
print(f"Python {sys.version.split()[0]}: OK")
PY

log "Checking tmux"
command -v tmux >/dev/null 2>&1 || fail "tmux is required for the canonical team spawn backend"
tmux -V

log "Checking ClawTeam"
command -v clawteam >/dev/null 2>&1 || fail "clawteam is not installed or not on PATH"
CLAWTEAM_BIN="$(command -v clawteam)"
clawteam --version

HEALTH_JSON="$(clawteam --json config health)" || fail "clawteam config health failed"
CLAWTEAM_HEALTH_JSON="$HEALTH_JSON" python3 - <<'PY'
import json
import os

health = json.loads(os.environ["CLAWTEAM_HEALTH_JSON"])
problems = []
if health.get("exists") is not True:
    problems.append("data directory does not exist")
if health.get("writable") is not True:
    problems.append("data directory is not writable")
latency = health.get("latency_ms", -1)
if not isinstance(latency, (int, float)) or latency < 0:
    problems.append("data directory read/write health probe did not complete")
if problems:
    detail = health.get("write_error")
    suffix = f" ({detail})" if detail else ""
    raise SystemExit("ClawTeam health failed: " + "; ".join(problems) + suffix)
print(
    f"ClawTeam data directory: exists=yes writable=yes latency_ms={latency}"
)
PY

if command -v openclaw >/dev/null 2>&1; then
  log "Checking OpenClaw integration"
  openclaw --version

  # Use the CLI as the policy source of truth so this works with both legacy
  # file-backed approvals and newer OpenClaw state storage.
  APPROVALS_JSON="$(openclaw approvals get --json)" || fail "unable to read effective OpenClaw approvals policy"
  REQUIRED_AGENTS="${PEFY_OPENCLAW_AGENT_IDS:-main}"

  OPENCLAW_APPROVALS_JSON="$APPROVALS_JSON" \
  PEFY_REQUIRED_AGENTS="$REQUIRED_AGENTS" \
  CLAWTEAM_BIN="$CLAWTEAM_BIN" \
  python3 - <<'PY'
import fnmatch
import json
import os
from pathlib import Path

raw = json.loads(os.environ["OPENCLAW_APPROVALS_JSON"])
required_agents = [
    item.strip()
    for item in os.environ.get("PEFY_REQUIRED_AGENTS", "main").split(",")
    if item.strip()
]
clawteam_bin = str(Path(os.environ["CLAWTEAM_BIN"]).expanduser().resolve())


def find_snapshot(value):
    """Find an approvals-policy object across OpenClaw JSON output variants."""
    if isinstance(value, dict):
        if isinstance(value.get("agents"), dict) and isinstance(value.get("defaults", {}), dict):
            return value
        # Prefer host/effective policy objects when present.
        for key in ("effective", "host", "approvals", "policy", "config"):
            if key in value:
                found = find_snapshot(value[key])
                if found is not None:
                    return found
        for child in value.values():
            found = find_snapshot(child)
            if found is not None:
                return found
    elif isinstance(value, list):
        for child in value:
            found = find_snapshot(child)
            if found is not None:
                return found
    return None


snapshot = find_snapshot(raw)
if snapshot is None:
    raise SystemExit("Could not locate OpenClaw approvals defaults/agents in JSON output")

defaults = snapshot.get("defaults") or {}
default_security = defaults.get("security")
if default_security != "allowlist":
    raise SystemExit(
        "OpenClaw exec approval default security must be 'allowlist' for PEFY production; "
        f"got {default_security!r}"
    )

agents = snapshot.get("agents") or {}
if not required_agents:
    raise SystemExit("No required OpenClaw agents configured for qualification")


def pattern_matches_clawteam(pattern):
    if not isinstance(pattern, str) or not pattern.strip():
        return False
    expanded = os.path.expanduser(pattern.strip())
    return (
        expanded in {"clawteam", "*/clawteam", "**/clawteam"}
        or fnmatch.fnmatch(clawteam_bin, expanded)
    )


for agent_id in required_agents:
    if agent_id == "*":
        raise SystemExit(
            "PEFY_OPENCLAW_AGENT_IDS must name concrete agents; wildcard-only qualification is not accepted"
        )
    cfg = agents.get(agent_id)
    if not isinstance(cfg, dict):
        raise SystemExit(f"OpenClaw approvals have no concrete policy for required agent {agent_id!r}")

    effective_security = cfg.get("security", default_security)
    if effective_security != "allowlist":
        raise SystemExit(
            f"OpenClaw agent {agent_id!r} effective security must be 'allowlist'; "
            f"got {effective_security!r}"
        )

    allowlist = cfg.get("allowlist") or []
    patterns = []
    for entry in allowlist:
        if isinstance(entry, str):
            patterns.append(entry)
        elif isinstance(entry, dict):
            pattern = entry.get("pattern")
            if isinstance(pattern, str):
                patterns.append(pattern)

    if not any(pattern_matches_clawteam(pattern) for pattern in patterns):
        raise SystemExit(
            f"Required OpenClaw agent {agent_id!r} does not explicitly allow the resolved "
            f"ClawTeam executable {clawteam_bin!r}. Add a concrete-agent allowlist rule first."
        )

print(
    "OpenClaw exec approvals: allowlist mode with explicit ClawTeam rule for "
    + ", ".join(required_agents)
)
PY

  if ! openclaw skills list | grep -qi 'clawteam'; then
    fail "OpenClaw does not report the ClawTeam skill as loaded"
  fi
  log "OpenClaw ClawTeam skill: OK"
else
  log "OpenClaw not present; ClawTeam may use another supported CLI agent, but PEFY default-runtime qualification is incomplete"
  exit 2
fi

log "Production qualification checks passed"
