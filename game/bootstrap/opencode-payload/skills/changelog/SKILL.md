---
name: changelog
description: "Old name of /write-changelog. Prints one line, then runs /write-changelog."
metadata:
  opencode/autoinvoke: true
---
> Uso: `[version|sprint-number]`


<!-- OpenCode V2 compatibility layer (was Claude Code) -->
## Entorno OpenCode

Esta skill viene de Claude Code. En OpenCode:

- `$CLAUDE_PROJECT_DIR` = raíz del proyecto (`.opencode/` está en `/home/unde/my-game`).
- `$CLAUDE_SKILL_DIR` = directorio de esta skill.
- Los bloques `!`comando`` son instrucciones de shell: **ejecútalos con la herramienta `shell`**, no los imprimas.
- Antes de ejecutar cualquier script `.sh` de esta skill, exporta:
  ```sh
  export CLAUDE_PROJECT_DIR=/home/unde/my-game
  export CLAUDE_SKILL_DIR=/home/unde/my-game/.opencode/skills/changelog
  ```
  (los scripts también tienen un fallback automático si no están definidas).
- `AskUserQuestion` -> herramienta `question`. `Agent`/`Task*` -> herramienta `subagent`.
- Niveles de modelo Claude (`sonnet`, `opus`, `haiku`) -> hereda el modelo de la sesión; ignora `model:` del frontmatter original.


# /changelog — old name of /write-changelog

Several AI tools keep `/changelog` for a command of their own, so this skill is now
`/write-changelog`.

1. Print this line exactly, as the first line of your reply:

   /changelog is now /write-changelog. Running /write-changelog.

2. Run the `write-changelog` skill with the Skill tool, passing these arguments unchanged
   (none, if this is empty): $ARGUMENTS

Do nothing else here: `/write-changelog` does the work.
