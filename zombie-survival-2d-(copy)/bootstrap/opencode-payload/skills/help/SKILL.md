---
name: help
description: "Old name of /next-step. Prints one line, then runs /next-step."
metadata:
  opencode/autoinvoke: true
---
> Uso: `[optional: what you just finished, e.g. 'finished design-review' or 'stuck on ADRs']`


<!-- OpenCode V2 compatibility layer (was Claude Code) -->
## Entorno OpenCode

Esta skill viene de Claude Code. En OpenCode:

- `$CLAUDE_PROJECT_DIR` = raíz del proyecto (`.opencode/` está en `/home/unde/my-game`).
- `$CLAUDE_SKILL_DIR` = directorio de esta skill.
- Los bloques `!`comando`` son instrucciones de shell: **ejecútalos con la herramienta `shell`**, no los imprimas.
- Antes de ejecutar cualquier script `.sh` de esta skill, exporta:
  ```sh
  export CLAUDE_PROJECT_DIR=/home/unde/my-game
  export CLAUDE_SKILL_DIR=/home/unde/my-game/.opencode/skills/help
  ```
  (los scripts también tienen un fallback automático si no están definidas).
- `AskUserQuestion` -> herramienta `question`. `Agent`/`Task*` -> herramienta `subagent`.
- Niveles de modelo Claude (`sonnet`, `opus`, `haiku`) -> hereda el modelo de la sesión; ignora `model:` del frontmatter original.


# /help — old name of /next-step

Most AI tools keep `/help` for a command of their own, so this skill is now
`/next-step`.

1. Print this line exactly, as the first line of your reply:

   /help is now /next-step. Running /next-step.

2. Run the `next-step` skill with the Skill tool, passing these arguments unchanged
   (none, if this is empty): $ARGUMENTS

Do nothing else here: `/next-step` does the work.
