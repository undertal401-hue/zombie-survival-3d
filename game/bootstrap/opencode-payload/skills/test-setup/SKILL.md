---
name: test-setup
description: "Sets up the test framework and CI: tests/ directory, engine runner, GitHub Actions workflow. Use once, before the first sprint."
metadata:
  opencode/autoinvoke: true
---
> Uso: `[force]`


<!-- OpenCode V2 compatibility layer (was Claude Code) -->
## Entorno OpenCode

Esta skill viene de Claude Code. En OpenCode:

- `$CLAUDE_PROJECT_DIR` = raíz del proyecto (`.opencode/` está en `/home/unde/my-game`).
- `$CLAUDE_SKILL_DIR` = directorio de esta skill.
- Los bloques `!`comando`` son instrucciones de shell: **ejecútalos con la herramienta `shell`**, no los imprimas.
- Antes de ejecutar cualquier script `.sh` de esta skill, exporta:
  ```sh
  export CLAUDE_PROJECT_DIR=/home/unde/my-game
  export CLAUDE_SKILL_DIR=/home/unde/my-game/.opencode/skills/test-setup
  ```
  (los scripts también tienen un fallback automático si no están definidas).
- `AskUserQuestion` -> herramienta `question`. `Agent`/`Task*` -> herramienta `subagent`.
- Niveles de modelo Claude (`sonnet`, `opus`, `haiku`) -> hereda el modelo de la sesión; ignora `model:` del frontmatter original.


!`bash "${CLAUDE_SKILL_DIR}/../../hooks/yaml-helper.sh" resolve_config --keys automation,workflow,qa.level`

**Automation mode**: Resolve `modes.automation` (`project.local.yaml` →
`project.yaml` → default `collaborative`). Every question and
every file write follows `.claude/docs/automation-modes.md`
(collaborative asks always · guided major-only · autonomous logs and proceeds;
`automation_always_ask` categories always prompt).

# Test Setup

This skill scaffolds the automated testing infrastructure for the project.
It detects the configured engine, generates the appropriate test runner
configuration, creates the standard directory layout, and wires up CI/CD
so tests run on every push.

Run this once during the Technical Setup phase, before any implementation
begins. A test framework installed at sprint start costs 30 minutes.
A test framework installed at sprint four costs 3 sprints.

**Output:** `tests/` directory structure + `.github/workflows/tests.yml`

---

## Phase 1: Detect Engine and Existing State

**Read `references/1-detect.md` now and follow it** — this phase's steps are in that file, not here. Read it again if the conversation was compacted or resumed during this phase.

## Phase 2: Present Plan

**Read `references/2-plan.md` now and follow it** — this phase's steps are in that file, not here. Read it again if the conversation was compacted or resumed during this phase.

## Phase 3: Create Directory Structure

**Read `references/3-directories.md` now and follow it** — this phase's steps are in that file, not here. Read it again if the conversation was compacted or resumed during this phase.

## Phase 4: Create CI/CD Workflow

**Read `references/4-ci.md` now and follow it** — this phase's steps are in that file, not here. Read it again if the conversation was compacted or resumed during this phase.

## Phase 5: Create Smoke Test Seed

**Read `references/5-smoke-seed.md` now and follow it** — this phase's steps are in that file, not here. Read it again if the conversation was compacted or resumed during this phase.

## Phase 6: Post-Setup Summary

**Read `references/6-summary.md` now and follow it** — this phase's steps are in that file, not here. Read it again if the conversation was compacted or resumed during this phase.

## Collaborative Protocol

- **Never overwrite existing test files** — only create files that are missing.
  If a test runner file exists, leave it as-is.
- **Always ask before creating files** — Phase 2 requires explicit approval.
- **Engine detection is non-negotiable** — if the engine is not configured,
  stop and redirect to `/setup-engine`. Do not guess.
- **`force` flag skips the "already exists" early-exit but never overwrites.**
  It means "create any missing files even if the directory already exists."
- For Unity CI, note that the `UNITY_LICENSE` secret must be configured
  manually. Do not attempt to automate license management.
