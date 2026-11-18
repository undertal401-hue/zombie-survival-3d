---
name: settings
description: "Old name of /project-settings. Prints one line, then runs /project-settings."
metadata:
  opencode/autoinvoke: true
---
> Uso: `[key | key=value | --local key=value]`


<!-- OpenCode V2 compatibility layer (was Claude Code) -->
## Entorno OpenCode

Esta skill viene de Claude Code. En OpenCode:

- `$CLAUDE_PROJECT_DIR` = raíz del proyecto (`.opencode/` está en `/home/unde/my-game`).
- `$CLAUDE_SKILL_DIR` = directorio de esta skill.
- Los bloques `!`comando`` son instrucciones de shell: **ejecútalos con la herramienta `shell`**, no los imprimas.
- Antes de ejecutar cualquier script `.sh` de esta skill, exporta:
  ```sh
  export CLAUDE_PROJECT_DIR=/home/unde/my-game
  export CLAUDE_SKILL_DIR=/home/unde/my-game/.opencode/skills/settings
  ```
  (los scripts también tienen un fallback automático si no están definidas).
- `AskUserQuestion` -> herramienta `question`. `Agent`/`Task*` -> herramienta `subagent`.
- Niveles de modelo Claude (`sonnet`, `opus`, `haiku`) -> hereda el modelo de la sesión; ignora `model:` del frontmatter original.


# /settings — old name of /project-settings

Several AI tools keep `/settings` for a command of their own, so this skill is now
`/project-settings`.

1. Print this line exactly, as the first line of your reply:

   /settings is now /project-settings. Running /project-settings.

2. Run the `project-settings` skill with the Skill tool, passing these arguments unchanged
   (none, if this is empty): $ARGUMENTS

Do nothing else here: `/project-settings` does the work.
