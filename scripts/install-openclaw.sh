#!/usr/bin/env bash
set -euo pipefail

# ─── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

ok()   { printf "${GREEN}[OK]${NC}    %s\n" "$*"; }
warn() { printf "${YELLOW}[WARN]${NC}  %s\n" "$*"; }
fail() { printf "${RED}[FAIL]${NC}  %s\n" "$*"; exit 1; }
info() { printf "${CYAN}[INFO]${NC}  %s\n" "$*"; }

# ─── Banner ───────────────────────────────────────────────────────────────────
printf "${BOLD}${CYAN}"
cat << 'BANNER'

   ██████╗██╗      █████╗ ██╗    ██╗████████╗███████╗ █████╗ ███╗   ███╗
  ██╔════╝██║     ██╔══██╗██║    ██║╚══██╔══╝██╔════╝██╔══██╗████╗ ████║
  ██║     ██║     ███████║██║ █╗ ██║   ██║   █████╗  ███████║██╔████╔██║
  ██║     ██║     ██╔══██║██║███╗██║   ██║   ██╔══╝  ██╔══██║██║╚██╔╝██║
  ╚██████╗███████╗██║  ██║╚███╔███╔╝   ██║   ███████╗██║  ██║██║ ╚═╝ ██║
   ╚═════╝╚══════╝╚═╝  ╚═╝ ╚══╝╚══╝    ╚═╝   ╚══════╝╚═╝  ╚═╝╚═╝     ╚═╝

  OpenClaw Installer
BANNER
printf "${NC}\n"

# ─── 1. Check Python 3.10+ ───────────────────────────────────────────────────
info "Checking Python version..."
if ! command -v python3 &>/dev/null; then
    fail "python3 is not installed. Please install Python 3.10 or later."
fi

PYTHON_VERSION=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
PYTHON_MAJOR=$(echo "$PYTHON_VERSION" | cut -d. -f1)
PYTHON_MINOR=$(echo "$PYTHON_VERSION" | cut -d. -f2)

if [[ "$PYTHON_MAJOR" -lt 3 ]] || { [[ "$PYTHON_MAJOR" -eq 3 ]] && [[ "$PYTHON_MINOR" -lt 10 ]]; }; then
    fail "Python 3.10+ is required (found $PYTHON_VERSION)."
fi
ok "Python $PYTHON_VERSION found."

# ─── 2. Check tmux ───────────────────────────────────────────────────────────
info "Checking tmux..."
if ! command -v tmux &>/dev/null; then
    fail "tmux is not installed. Install it with: brew install tmux (macOS) or apt install tmux (Linux)."
fi
ok "tmux found: $(tmux -V)"

# ─── 3. Check openclaw ───────────────────────────────────────────────────────
info "Checking openclaw..."
OPENCLAW_CMD=()
if command -v openclaw &>/dev/null; then
    OPENCLAW_CMD=(openclaw)
elif python3 -m openclaw --version &>/dev/null 2>&1; then
    OPENCLAW_CMD=(python3 -m openclaw)
else
    fail "openclaw is not installed. Install it first: pip install openclaw"
fi
ok "openclaw found: $("${OPENCLAW_CMD[@]}" --version 2>/dev/null || echo 'installed')"

# ─── 4. Install clawteam ─────────────────────────────────────────────────────
info "Installing clawteam..."

# Determine the script's own directory and the repo root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

if [[ -f "$REPO_ROOT/pyproject.toml" ]] && grep -q 'name.*=.*"clawteam"' "$REPO_ROOT/pyproject.toml" 2>/dev/null; then
    info "Installing from local repo: $REPO_ROOT"
    pip install -e "$REPO_ROOT" --quiet 2>&1 | tail -3 || pip install "$REPO_ROOT" --quiet 2>&1 | tail -3
else
    info "Installing from PyPI..."
    pip install clawteam --quiet 2>&1 | tail -3
fi
ok "clawteam installed."

# ─── 5. Find clawteam binary location ────────────────────────────────────────
info "Locating clawteam binary..."
CLAWTEAM_BIN=""

# Method 1: command -v
if command -v clawteam &>/dev/null; then
    CLAWTEAM_BIN="$(command -v clawteam)"
fi

# Method 2: pip show + Scripts/bin dir
if [[ -z "$CLAWTEAM_BIN" ]]; then
    SITE_PKG="$(pip show clawteam 2>/dev/null | grep -i '^Location:' | awk '{print $2}')"
    if [[ -n "$SITE_PKG" ]]; then
        # Typical bin is one level up from site-packages, in a bin/ directory
        CANDIDATE="$(dirname "$(dirname "$SITE_PKG")")/bin/clawteam"
        if [[ -x "$CANDIDATE" ]]; then
            CLAWTEAM_BIN="$CANDIDATE"
        fi
    fi
fi

# Method 3: common paths
if [[ -z "$CLAWTEAM_BIN" ]]; then
    for p in \
        "$HOME/.local/bin/clawteam" \
        "/usr/local/bin/clawteam" \
        "/opt/homebrew/bin/clawteam" \
        "$HOME/Library/Python/3.*/bin/clawteam" \
        "/Library/Frameworks/Python.framework/Versions/3.*/bin/clawteam"; do
        # shellcheck disable=SC2086
        for expanded in $p; do
            if [[ -x "$expanded" ]]; then
                CLAWTEAM_BIN="$expanded"
                break 2
            fi
        done
    done
fi

if [[ -z "$CLAWTEAM_BIN" ]]; then
    fail "Could not locate the clawteam binary. Ensure pip's bin directory is in your PATH."
fi
ok "clawteam binary found at: $CLAWTEAM_BIN"

CLAWTEAM_RESOLVED="$(python3 - "$CLAWTEAM_BIN" <<'PY'
from pathlib import Path
import sys
print(Path(sys.argv[1]).expanduser().resolve())
PY
)"

# ─── 6. Create symlink at ~/bin/clawteam ──────────────────────────────────────
info "Setting up ~/bin/clawteam symlink..."
mkdir -p "$HOME/bin"

if [[ -L "$HOME/bin/clawteam" ]]; then
    EXISTING_TARGET="$(readlink "$HOME/bin/clawteam")"
    if [[ "$EXISTING_TARGET" == "$CLAWTEAM_BIN" ]]; then
        ok "Symlink already correct: ~/bin/clawteam -> $CLAWTEAM_BIN"
    else
        ln -sf "$CLAWTEAM_BIN" "$HOME/bin/clawteam"
        ok "Symlink updated: ~/bin/clawteam -> $CLAWTEAM_BIN"
    fi
elif [[ -e "$HOME/bin/clawteam" ]]; then
    warn "~/bin/clawteam already exists and is not a symlink. Skipping."
else
    ln -s "$CLAWTEAM_BIN" "$HOME/bin/clawteam"
    ok "Symlink created: ~/bin/clawteam -> $CLAWTEAM_BIN"
fi

# ─── 7. Verify ~/bin is in PATH ──────────────────────────────────────────────
info "Checking PATH..."
if echo "$PATH" | tr ':' '\n' | grep -qx "$HOME/bin"; then
    ok "~/bin is in PATH."
else
    warn "~/bin is NOT in your PATH."
    echo ""
    printf "${YELLOW}  Add one of these lines to your shell profile (~/.zshrc or ~/.bashrc):${NC}\n"
    echo ""
    echo "    export PATH=\"\$HOME/bin:\$PATH\""
    echo ""
fi

# ─── 8. Copy SKILL.md ────────────────────────────────────────────────────────
info "Installing OpenClaw skill file..."
SKILL_SRC="$REPO_ROOT/skills/openclaw/SKILL.md"
SKILL_DST="$HOME/.openclaw/workspace/skills/clawteam/SKILL.md"

if [[ ! -f "$SKILL_SRC" ]]; then
    warn "Source skill file not found at $SKILL_SRC — skipping skill copy."
else
    mkdir -p "$(dirname "$SKILL_DST")"
    cp "$SKILL_SRC" "$SKILL_DST"
    ok "Skill file installed to $SKILL_DST"
fi

# ─── 9. Configure exec approvals ─────────────────────────────────────────────
info "Configuring exec approvals for ClawTeam..."
REQUIRED_AGENTS="${PEFY_OPENCLAW_AGENT_IDS:-main}"

# Prefer the current normalized OpenClaw policy surface. Fall back to the legacy
# approvals file only when the installed OpenClaw does not support tools.exec.mode.
if "${OPENCLAW_CMD[@]}" config set tools.exec.mode allowlist &>/dev/null; then
    ok "OpenClaw requested exec mode set to allowlist"
else
    STATE_ROOT="${OPENCLAW_STATE_DIR:-$HOME/.openclaw}"
    APPROVALS_FILE="$STATE_ROOT/exec-approvals.json"
    if [[ -f "$APPROVALS_FILE" ]]; then
        python3 - "$APPROVALS_FILE" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
data = json.loads(path.read_text())
data.setdefault("defaults", {})["security"] = "allowlist"
path.write_text(json.dumps(data, indent=2) + "\n")
PY
        ok "Legacy exec approvals security set to allowlist"
    else
        warn "Could not set tools.exec.mode and no legacy exec-approvals.json was found"
    fi
fi

APPROVALS_FAILED=0
IFS=',' read -r -a AGENT_IDS <<< "$REQUIRED_AGENTS"
for RAW_AGENT_ID in "${AGENT_IDS[@]}"; do
    AGENT_ID="$(printf '%s' "$RAW_AGENT_ID" | xargs)"
    [[ -n "$AGENT_ID" ]] || continue
    if [[ "$AGENT_ID" == "*" ]]; then
        warn "Wildcard agent '*' is not accepted for PEFY production qualification; name concrete agents instead"
        APPROVALS_FAILED=1
        continue
    fi
    if "${OPENCLAW_CMD[@]}" approvals allowlist add --agent "$AGENT_ID" "$CLAWTEAM_RESOLVED" &>/dev/null; then
        ok "Allowlisted ClawTeam for OpenClaw agent: $AGENT_ID"
    else
        warn "Could not add ClawTeam to the allowlist for agent $AGENT_ID"
        APPROVALS_FAILED=1
    fi
done

if [[ "$APPROVALS_FAILED" -ne 0 ]]; then
    fail "OpenClaw approvals configuration is incomplete"
fi

# ─── 10. Verify clawteam --version ───────────────────────────────────────────
info "Verifying installation..."
if "$CLAWTEAM_BIN" --version &>/dev/null; then
    CT_VERSION="$("$CLAWTEAM_BIN" --version 2>&1)"
    ok "clawteam --version: $CT_VERSION"
else
    fail "clawteam --version did not return cleanly"
fi

# ─── 11. Run production qualification ────────────────────────────────────────
QUALIFIER="$REPO_ROOT/scripts/verify-pefy-production.sh"
if [[ -f "$QUALIFIER" ]]; then
    info "Running PEFY production qualification..."
    PEFY_OPENCLAW_AGENT_IDS="$REQUIRED_AGENTS" bash "$QUALIFIER" || \
        fail "PEFY production qualification failed"
    ok "PEFY production qualification passed"
else
    warn "Production qualifier not found at $QUALIFIER"
fi

# ─── 12. Success ──────────────────────────────────────────────────────────────
echo ""
printf "${BOLD}${GREEN}"
cat << 'MSG'
  ╔═══════════════════════════════════════════════════╗
  ║   Installation complete! ClawTeam is ready.       ║
  ╚═══════════════════════════════════════════════════╝
MSG
printf "${NC}\n"
info "Run 'clawteam --help' to get started."
