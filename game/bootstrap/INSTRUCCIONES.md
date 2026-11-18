# Bootstrap: OpenCode V2 + nuestro taller de juego en Arch base

Lee esto en el sistema nuevo. Objetivo: clonar este repo, seguir los pasos y continuar exactamente donde estábamos — mismos **49 agentes**, **78 skills**, **5 MCPs** y la misma forma de trabajar. Sin empezar de cero.

Convenciones: usuario `unde`, rutas `/home/unde/...`. **No cambies la ruta `~/my-game`**: OpenCode asocia las sesiones al directorio; si cambia, el chat sigue en la base de datos pero aparece como otro proyecto.

---

## 0. ANTES de formatear (en el sistema actual)

Este chat **no está en GitHub**: vive en `~/.local/share/opencode/opencode.db`. Sálvalo:

```sh
DEST=/run/media/unde/TU_DISCO/arch-migrate
mkdir -p "$DEST"
sqlite3 ~/.local/share/opencode/opencode.db ".backup '$DEST/opencode.db'"
cp -a ~/.config/opencode/cli.json "$DEST/cli.json"
cp -a ~/.config/opencode/opencode.jsonc "$DEST/opencode.jsonc.OLD"   # tiene un token: NO subir a git
tar -C /home/unde -cf "$DEST/work.tar" flat_world/game my-game       # incluye cambios sin commitear
sha256sum "$DEST"/* > "$DEST/SHA256SUMS"
```

Guarda el `SHA256SUMS` en otro sitio. **Nunca subas el backup a un repo público.**

---

## 1. Arch base: instala todo lo que uso

```sh
sudo pacman -Syu
sudo pacman -S --needed git nodejs npm python python-pip sqlite curl jq unzip wget base-devel
curl -LsSf https://astral.sh/uv/install.sh | sh          # uv / uvx -> MCP de godot-ai
gh auth login                                            # scopes: repo, workflow, read:org
curl -fsSL opencode.ai/v2/install | bash                 # OpenCode V2
opencode --version
```

Godot 4.7 (el juego corre en 4.7.2):

```sh
sudo pacman -S godot
godot --version
```

HexStrike (150+ herramientas de seguridad, servidor en `:8888`):

```sh
sudo pacman -S --needed nmap masscan ffuf gobuster nuclei nikto sqlmap hydra john hashcat
git clone https://github.com/0x4m4/hexstrike-ai.git /opt/hexstrike-ai
python3 -m venv /opt/hexstrike-ai/venv
/opt/hexstrike-ai/venv/bin/pip install -r /opt/hexstrike-ai/requirements.txt
/opt/hexstrike-ai/venv/bin/pip install requests mcp
(cd /opt/hexstrike-ai && nohup /opt/hexstrike-ai/venv/bin/python hexstrike_server.py --port 8888 > /tmp/hexstrike.log 2>&1 &)
curl http://127.0.0.1:8888/health
```

---

## 2. Clona

```sh
cd /home/unde
git clone https://github.com/undertal401-hue/zombie-survival-3d.git
git clone https://github.com/Donchitos/Claude-Code-Game-Studios.git my-game
```

El segundo trae los 78 skills y 49 agentes originales en `.claude/`.

---

## 3. Skills y agentes: cópialos ya convertidos

`bootstrap/opencode-payload/` es la conversión a OpenCode V2 de `.claude/` (frontmatter V2, compat layer, rutas y scripts `.sh` parcheados). No hay que regenerar nada:

```sh
cp -a /home/unde/zombie-survival-3d/bootstrap/opencode-payload /home/unde/my-game/.opencode
cp /home/unde/zombie-survival-3d/bootstrap/opencode.json /home/unde/my-game/opencode.json
ls /home/unde/my-game/.opencode/skills | wc -l    # 78
ls /home/unde/my-game/.opencode/agents | wc -l    # 49
```

Si quieres reconvertir desde el upstream, pídele a OpenCode: *«convierte `.claude/` a `.opencode/` aplicando el compat layer de `bootstrap/`»*. Enlaces guardados:

- Skills/agentes: https://github.com/Donchitos/Claude-Code-Game-Studios
- Bridge Godot MCP: https://github.com/NPGameDev/godot-mcp-server
- Servidor godot-ai: https://github.com/hi-godot/godot-ai · https://pypi.org/project/godot-ai/
- HexStrike: https://github.com/0x4m4/hexstrike-ai
- Documentación OpenCode V2: https://opencode.ai/docs

---

## 4. MCPs (GitHub, Godot, HexStrike)

Escribe `~/.config/opencode/opencode.jsonc`. En V2 los nombres van bajo `mcp.servers`, **no** directamente bajo `mcp`:

```jsonc
{
  "$schema": "https://opencode.ai/config.json",
  "mcp": {
    "servers": {
      "github": {
        "type": "remote",
        "url": "https://api.githubcopilot.com/mcp/"
      },
      "godot-ai": {
        "type": "local",
        "command": [
          "uvx", "--isolated", "--no-config", "--no-env-file", "--no-sources",
          "--no-build", "--index-strategy", "first-index",
          "--index", "https://pypi.org/simple",
          "--default-index", "https://pypi.org/simple/godot-ai/",
          "--find-links", "https://pypi.org/simple/godot-ai/",
          "--from", "godot-ai==4.3.1", "godot-ai"
        ]
      },
      "godot-mcp-server": {
        "type": "local",
        "command": ["npx", "-y", "@npgamedev/godot-mcp-server"],
        "environment": {
          "GODOT_MCP_PROJECT_PATH": "/home/unde/zombie-survival-3d"
        }
      },
      "hexstrike": {
        "type": "local",
        "command": [
          "/opt/hexstrike-ai/venv/bin/python",
          "/opt/hexstrike-ai/hexstrike_mcp.py",
          "--server", "http://127.0.0.1:8888"
        ]
      },
      "gemini-api-docs-mcp": {
        "type": "remote",
        "url": "https://gemini-api-docs-mcp.dev"
      }
    }
  }
}
```

Notas:

- **GitHub**: tras `gh auth login`, abre OpenCode y ejecuta `/mcps` → `github` → sign in. Si tu instancia pide token, añade `"headers": {"Authorization": "Bearer {env:GH_TOKEN}"}` y exporta `GH_TOKEN=$(gh auth token)`. **No pegues un token en el archivo.**
- **Godot**: ajusta `GODOT_MCP_PROJECT_PATH` a la ruta real del juego.
- **godot-ai**: `uvx` viene del paso 1. Si `4.3.1` no existe, cambia `--from godot-ai==4.3.1` por la última versión de https://pypi.org/project/godot-ai/.
- **HexStrike**: el comando apunta a `/opt/hexstrike-ai/...` y al servidor levantado en el paso 1.
- **gemini-api-docs-mcp**: remoto, sin instalación.

Verifica: `opencode mcp list` → deben aparecer los 5 conectados.

---

## 5. Restaurar este chat

```sh
mkdir -p ~/.local/share/opencode ~/.config/opencode
cp "$DEST/opencode.db" ~/.local/share/opencode/opencode.db
cp "$DEST/cli.json" ~/.config/opencode/cli.json
# NO restaures opencode.jsonc.OLD: token caducado. Reautentica con gh /mcps.
```

Mantén usuario `unde` y ruta idéntica. Es lo que evita empezar de cero conmigo.

---

## 6. Comprobación final

```sh
cd /home/unde/my-game && opencode
# dentro: /skills (78), /agents (49), /mcps (5) y el historial de esta conversación

cd /home/unde/zombie-survival-3d
godot --headless --path . --editor --quit
godot --headless --path . res://10_review/TestFixes.tscn
```

Esperado: `SCRIPT ERROR=0`, checks **40–54 OK**, `mechanics_ready=OK active=5/5`.

---

## Nuestra forma de trabajo (no negociable)

1. **Pregunta → Opciones → Decisión → Borrador → Aprobación.** Siempre.
2. Tú decides. Yo presento 2–4 opciones con pros/contras y una recomendación, pero nunca tomo la decisión final.
3. **No escribir archivos sin permiso**: antes pregunto «¿Puedo escribir esto en [ruta]?». Excepciones: apéndices a `production/session-state/active.md` y memoria de agente.
4. Subagentes solo cuando hay paralelismo real; si no, trabajo directo.
5. **Commits y push solo si lo pides explícitamente.** (Este bootstrap se subió por instrucción directa.)
6. Godot = verdad de implementación; los docs = verdad de diseño. Si cambia un número en código, se propaga al documento, no al revés.
7. Todo reversible: `git restore` o reclonar. Sin miedo a fracasar.
8. Realismo sobre lo genérico: si un efecto se siente sintético (lluvia, sprites, audio), se sustituye por grabación/textura real, no se acepta «es suficiente».

Orden sugerido al retomar el juego: `/reverse-document` → `/team-audio` → `/team-combat` + `/team-polish` → `/smoke-check` + `/qa-plan` + `/perf-profile`.
