from __future__ import annotations

import json
import os
import subprocess
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
SCRIPT = REPO_ROOT / "scripts" / "verify-pefy-production.sh"


def _write_executable(path: Path, content: str) -> None:
    path.write_text(content, encoding="utf-8")
    path.chmod(0o755)


def _run_qualification(tmp_path: Path, *, health: dict, approvals: dict) -> subprocess.CompletedProcess[str]:
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    home_dir = tmp_path / "home"
    home_dir.mkdir()

    _write_executable(
        bin_dir / "tmux",
        "#!/bin/sh\necho 'tmux 3.4'\n",
    )
    _write_executable(
        bin_dir / "clawteam",
        """#!/bin/sh
if [ "$1" = "--version" ]; then
  echo "clawteam v0.test"
  exit 0
fi
if [ "$1" = "--json" ] && [ "$2" = "config" ] && [ "$3" = "health" ]; then
  printf '%s\\n' "$FAKE_CLAWTEAM_HEALTH"
  exit 0
fi
exit 1
""",
    )
    _write_executable(
        bin_dir / "openclaw",
        """#!/bin/sh
if [ "$1" = "--version" ]; then
  echo "openclaw test"
  exit 0
fi
if [ "$1" = "approvals" ] && [ "$2" = "get" ] && [ "$3" = "--json" ]; then
  printf '%s\\n' "$FAKE_OPENCLAW_APPROVALS"
  exit 0
fi
if [ "$1" = "skills" ] && [ "$2" = "list" ]; then
  echo "clawteam loaded"
  exit 0
fi
exit 1
""",
    )

    resolved_clawteam = str((bin_dir / "clawteam").resolve())
    normalized_approvals = json.loads(json.dumps(approvals))
    for agent in normalized_approvals.get("agents", {}).values():
        for entry in agent.get("allowlist", []):
            if isinstance(entry, dict) and entry.get("pattern") == "__CLAWTEAM_BIN__":
                entry["pattern"] = resolved_clawteam

    env = os.environ.copy()
    env.update(
        {
            "PATH": f"{bin_dir}:{env.get('PATH', '')}",
            "HOME": str(home_dir),
            "FAKE_CLAWTEAM_HEALTH": json.dumps(health),
            "FAKE_OPENCLAW_APPROVALS": json.dumps(normalized_approvals),
            "PEFY_OPENCLAW_AGENT_IDS": "main",
        }
    )
    return subprocess.run(
        ["bash", str(SCRIPT)],
        cwd=REPO_ROOT,
        env=env,
        text=True,
        capture_output=True,
        check=False,
    )


def _healthy() -> dict:
    return {
        "data_dir": "/tmp/clawteam",
        "data_dir_source": "test",
        "exists": True,
        "writable": True,
        "latency_ms": 1.0,
        "is_mount": False,
        "teams_count": 0,
        "user": "test",
        "user_source": "test",
    }


def _approved() -> dict:
    return {
        "version": 1,
        "defaults": {"security": "deny", "ask": "on-miss"},
        "agents": {
            "main": {
                "security": "allowlist",
                "ask": "on-miss",
                "allowlist": [{"pattern": "__CLAWTEAM_BIN__"}],
            }
        },
    }


def test_production_qualification_passes_with_healthy_runtime(tmp_path: Path) -> None:
    result = _run_qualification(tmp_path, health=_healthy(), approvals=_approved())
    assert result.returncode == 0, result.stdout + result.stderr
    assert "Production qualification checks passed" in result.stdout


def test_production_qualification_fails_when_data_directory_is_unwritable(tmp_path: Path) -> None:
    health = _healthy()
    health.update({"writable": False, "latency_ms": -1, "write_error": "permission denied"})

    result = _run_qualification(tmp_path, health=health, approvals=_approved())

    assert result.returncode != 0
    assert "data directory is not writable" in result.stderr


def test_production_qualification_requires_concrete_agent_clawteam_allowlist(tmp_path: Path) -> None:
    approvals = {
        "version": 1,
        "defaults": {"security": "allowlist", "ask": "on-miss"},
        "agents": {
            "*": {
                "security": "allowlist",
                "allowlist": [{"pattern": "*/clawteam"}],
            },
            "main": {"security": "allowlist", "allowlist": []},
        },
    }

    result = _run_qualification(tmp_path, health=_healthy(), approvals=approvals)

    assert result.returncode != 0
    assert "does not explicitly allow" in result.stderr


def test_production_qualification_rejects_always_prompt_policy(tmp_path: Path) -> None:
    approvals = _approved()
    approvals["agents"]["main"]["ask"] = "always"

    result = _run_qualification(tmp_path, health=_healthy(), approvals=approvals)

    assert result.returncode != 0
    assert "would block on prompts" in result.stderr
