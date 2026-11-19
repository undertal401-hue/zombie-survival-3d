#!/usr/bin/env bash
# run_loop_5h.sh — Loop autónomo de ~5 horas de rondas de mejora del juego.
#
# Cada ronda auto-invoca al agente CLI, que delega en 4 subagentes especializados
# (Visual/Shaders, Gameplay/Armas-Zombis, QA/Diagnóstico, Documentación/Obsidian),
# consolida, verifica con Godot headless y escribe en la bitácora de Obsidian.
#
# Configurable por entorno:
#   ROUNDS=25 PAUSE_SECONDS=600 ROUND_TIMEOUT=1800 ./run_loop_5h.sh
# Parar limpiamente: crear el archivo loop.stop (ver STOP_FILE).

set -u

REPO="/home/unde/zombie-survival-3d"
VAULT="/home/unde/vault/vault/Auditoria_Videojuego"
LOG_FILE="$VAULT/loop_stdout.log"
STOP_FILE="$VAULT/loop.stop"

ROUNDS="${ROUNDS:-25}"
PAUSE_SECONDS="${PAUSE_SECONDS:-600}"
ROUND_TIMEOUT="${ROUND_TIMEOUT:-1800}"

log() { printf '%s %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$*"; }

# --- Detección automática del CLI del agente en este entorno -----------------
CLI_BIN=""
CLI_MODE=""
if command -v opencode >/dev/null 2>&1 && opencode run --help >/dev/null 2>&1; then
    CLI_BIN="opencode"
    CLI_MODE="opencode"
elif command -v claude >/dev/null 2>&1; then
    CLI_BIN="claude"
    CLI_MODE="claude"
elif command -v codex >/dev/null 2>&1; then
    CLI_BIN="codex"
    CLI_MODE="codex"
else
    log "FATAL: no se encontró ningún CLI de agente (opencode/claude/codex). Aborto."
    exit 1
fi
log "CLI detectado: $CLI_BIN (modo $CLI_MODE)"

cd "$REPO" || { log "FATAL: no puedo entrar a $REPO"; exit 1; }

# --- Prompt autocontenido de cada ronda --------------------------------------
read -r -d '' ROUND_PROMPT <<'PROMPT' || true
Eres el LEAD ORCHESTRATOR de Zombie Survival 2D (Godot 4.7, GDScript) en /home/unde/zombie-survival-3d. Estás ejecutando UNA ronda del loop de 5 horas. Trabaja de forma autónoma: NO pidas permiso al usuario.

PASO 1 — CONTEXTO. Lee:
  /home/unde/vault/vault/Auditoria_Videojuego/00_Indice_General.md
  /home/unde/vault/vault/Auditoria_Videojuego/04_Deuda_Tecnica_Bugs_y_Mejoras.md
  /home/unde/vault/vault/Auditoria_Videojuego/05_Expansion_y_Cambios.md
  /home/unde/vault/vault/Auditoria_Videojuego/06_Loop_5Horas_Bitacora.md
Elige 1-2 elementos concretos y de bajo riesgo de la deuda abierta para esta ronda. NO rehagas las Fases 1-5 (arsenal, separación O(N·k), CI, dificultad unificada ya están hechos): verifícalos y corrige solo huecos reales.

PASO 2 — DELEGA EN 4 SUBAGENTES con herramientas de subagente. Dales contexto completo y superficies de escritura AISLADAS para evitar conflictos:
  A) Visual/Shaders/Sprites -> assets/shaders/*, 08_ui/*.gdshader, SolarGlareMaterial.tres, 02_player/PlayerVisual.gd, 03_zombies/ZombieVisual.gd. Compilar todos los .gdshader, auditar rutas de sprites/materiales en .tscn (solo auditoría, no editar .tscn), hasta 2 mejoras seguras.
  B) Gameplay/Armas/Zombis -> 02_player/weapons/{WeaponController,Weapon}.gd, los 4 .tres, 03_zombies/Zombie.gd y Zombie.tscn. Verificar 4 armas cableadas y 5 arquetipos diferenciados con separación O(N·k); cerrar huecos como la señal zombie_alerted muerta (#17) o la caché _connected_weapons que solo crece (#18).
  C) QA/Diagnóstico -> 10_review/*, 09_tests/QA.*, .github/workflows/ci.yml. Auditar sintaxis, res:// rotos, señales/estados; reforzar arneses con assert() reales.
  D) Documentación/Obsidian -> las notas 06, 04 y 00 del vault. Ejecútalo AL FINAL, con los reportes de A/B/C en el prompt, para que registre qué delegó cada uno, qué cambió y qué queda pendiente con wikilinks [[...]] y etiquetas #videojuego #arquitectura #devlog.
Regla: ningún subagente hace git add/commit/push. Tú consolidas y resuelves conflictos.

PASO 3 — VERIFICACIÓN OBLIGATORIA (ejecuta de verdad, guarda marcas):
  cd /home/unde/zombie-survival-3d/game
  godot --headless --path . --editor --quit
  godot --headless --path . res://10_review/TestFixes.tscn --quit-after 700
  godot --headless --path . res://10_review/SeparationTest.tscn --quit-after 700
  godot --headless --path . res://10_review/ArsenalTest.tscn --quit-after 700
  godot --headless --path . res://10_review/AiWaveTest.tscn --quit-after 700
  QA_MODE=mechanics godot --headless --path . res://09_tests/QA.tscn --quit-after 700
COMPUERTA: exige que aparezcan HARD_GATE failures=0, SEPARATION_TEST failures=0, ARSENAL_TEST failures=0, AI_WAVE_TEST failures=0 y MECHANICS_READY 5/5, sin SCRIPT ERROR ni Parse Error. Si algún cambio rompe la compuerta, REVIÉRTELO y repite hasta que pase. Nunca reportes OK sin estas marcas.

PASO 4 — DOCUMENTAR y COMMIT. Asegúrate de que el subagente D actualizó 06/04/00. Luego, SOLO si la compuerta pasó:
  cd /home/unde/zombie-survival-3d
  git add -A && git commit -m "Loop ronda: <resumen corto>" && git push origin main
Si la compuerta falla, NO hagas commit: documenta el fallo en 06 y deja el working tree revertido a verde.

PASO 5 — Termina con una línea machine-readable exacta:
  ROUND_RESULT status=OK|FAIL changes=<n> commit=<sha|none> summary="<una línea>"
Sé honesto: no inventes comandos ni marcas que no obtuviste.
PROMPT

log "LOOP_START rounds=$ROUNDS pause=${PAUSE_SECONDS}s timeout=${ROUND_TIMEOUT}s pid=$$"

i=1
while [ "$i" -le "$ROUNDS" ]; do
    if [ -f "$STOP_FILE" ]; then
        log "STOP_FILE detectado. Saliendo limpiamente antes de la ronda $i."
        break
    fi

    log "===== ROUND_START r=$i ====="
    round_rc=0
    if [ "$CLI_MODE" = "opencode" ]; then
        timeout "$ROUND_TIMEOUT" opencode run --auto \
            --title "Loop 5h · Ronda $i" \
            "$ROUND_PROMPT" 2>&1
        round_rc=$?
    elif [ "$CLI_MODE" = "claude" ]; then
        timeout "$ROUND_TIMEOUT" claude -p --dangerously-skip-permissions "$ROUND_PROMPT" 2>&1
        round_rc=$?
    else
        timeout "$ROUND_TIMEOUT" codex exec "$ROUND_PROMPT" 2>&1
        round_rc=$?
    fi

    if [ "$round_rc" -eq 124 ]; then
        log "ROUND_TIMEOUT r=$i (>$ROUND_TIMEOUT s)"
    elif [ "$round_rc" -ne 0 ]; then
        log "ROUND_ERROR r=$i exit=$round_rc"
    fi

    log "===== ROUND_END r=$i exit=$round_rc ====="

    if [ "$i" -lt "$ROUNDS" ]; then
        log "SLEEP ${PAUSE_SECONDS}s (ronda $i -> $((i+1)))"
        # Dormir en bloques cortos para reaccionar rápido al STOP_FILE.
        slept=0
        while [ "$slept" -lt "$PAUSE_SECONDS" ]; do
            [ -f "$STOP_FILE" ] && break
            sleep 30
            slept=$((slept + 30))
        done
    fi
    i=$((i + 1))
done

log "LOOP_END pid=$$ rounds_done=$((i-1))"
