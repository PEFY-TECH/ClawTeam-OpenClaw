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
clawteam --version
clawteam config health

if command -v openclaw >/dev/null 2>&1; then
  log "Checking OpenClaw integration"
  openclaw --version

  APPROVALS_FILE="${HOME}/.openclaw/exec-approvals.json"
  [[ -f "${APPROVALS_FILE}" ]] || fail "${APPROVALS_FILE} is required for production qualification"

  python3 - "${APPROVALS_FILE}" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
data = json.loads(path.read_text())
security = data.get("defaults", {}).get("security")
if security != "allowlist":
    raise SystemExit(
        f"OpenClaw exec approval security must be 'allowlist' for PEFY production; got {security!r}"
    )
print("OpenClaw exec approval security: allowlist")
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
