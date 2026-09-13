# PEFY ClawTeam Production Qualification

## Role

`PEFY-TECH/ClawTeam-OpenClaw` is the canonical multi-agent coordination and execution plane for the PEFY Agent Workforce. It operates below Mission Control and above the selected agent runtime.

Repository presence, installation, or a mergeable pull request does not constitute production activation.

## Qualification states

- **Registered** — ClawTeam is the selected execution-plane component.
- **Code candidate** — hardening changes exist on a review branch.
- **Code qualified** — the exact candidate SHA passes review and the required CI matrix.
- **Runtime qualified** — the exact code-qualified version passes `scripts/verify-pefy-production.sh` on the approved OpenClaw host.
- **Live production active** — runtime-qualified ClawTeam completes an auditable controlled multi-agent mission in the approved environment with monitoring and rollback evidence.

## Current code controls

The production qualifier is fail-closed and requires:

- Python 3.10 or later;
- `tmux` for the canonical team spawning backend;
- a resolvable ClawTeam executable;
- a ClawTeam coordination directory that exists and passes actual read/write health checks;
- OpenClaw present for the canonical PEFY runtime path;
- effective OpenClaw approvals readable through the OpenClaw CLI;
- concrete OpenClaw agent IDs rather than wildcard-only qualification;
- effective `allowlist` execution policy for every required agent;
- an explicit allowlist rule matching the resolved ClawTeam executable;
- no blocking `ask=always` policy for unattended agent coordination;
- the ClawTeam OpenClaw skill loaded.

The qualifier does not accept unrestricted `full` execution merely to make automation work.

## Review remediation

Two P1 findings identified during review of the original qualifier were remediated:

1. an unhealthy or unwritable ClawTeam coordination directory could previously allow a false-positive qualification;
2. `allowlist` security mode could previously pass without proving the actual ClawTeam executable was allowed for the required agent.

Regression tests now cover the healthy path and these fail-closed conditions, including wildcard-only approval and blocking prompt-policy cases.

## CI requirement

The repository workflow must execute successfully for the exact candidate SHA. Required evidence includes:

- Ruff/lint;
- shell syntax validation for qualification tooling;
- Ubuntu test matrix for Python 3.10, 3.11 and 3.12;
- macOS test matrix for Python 3.10, 3.11 and 3.12.

If GitHub Actions does not launch, this gate remains **BLOCKED**, even when the PR is mergeable or local regression checks pass.

## Runtime requirement

After code qualification and merge, execute on the approved host:

```bash
PEFY_OPENCLAW_AGENT_IDS="main" bash scripts/verify-pefy-production.sh
```

Use the actual approved concrete agent IDs for the environment.

Runtime qualification must record, without secrets:

- ClawTeam version and immutable source/package reference;
- OpenClaw version and immutable runtime reference;
- concrete agent IDs;
- coordination-storage health;
- effective allowlist policy result;
- ClawTeam skill presence;
- gateway/runtime health;
- logs and audit reference.

## Controlled multi-agent acceptance mission

The live acceptance mission must use non-destructive test scope and prove:

1. Mission Control creates or exposes the task;
2. a team lead is assigned;
3. at least one worker is spawned;
4. parallel code work uses isolated Git worktrees;
5. task dependencies/DAG are observable;
6. agent-to-agent coordination is observable;
7. one approved low-risk action succeeds;
8. one unauthorized or approval-gated action is denied or routed for approval;
9. the resulting artifact is inspectable;
10. organization/board/task/agent/repository/ref/outcome traceability is preserved without secret leakage.

## Dependencies on the wider PEFY stack

ClawTeam cannot be declared live production active independently of its runtime. The selected OpenClaw runtime must itself be code-qualified and runtime-qualified. If OpenClaw is blocked by provenance, drift, CI, security, compatibility or host evidence, ClawTeam runtime promotion is also blocked.

## Promotion rule

Promotion is deny-by-default. Do not merge a production-qualification candidate or declare runtime activation based only on a review branch, local test output, repository availability, or intended deployment. Objective CI and real-host evidence are mandatory.
