# TDD evidence — FASE 1, punto 8: pueblos abiertos a pie

## Requisito

Los pueblos deben recorrerse caminando desde el campo. No puede quedar una
barricada física ni un cartel `CERRADO` en el asentamiento principal. Los
pueblos secundarios deben seguir presentes y conectados por caminos.

## RED

Checkpoint commit: `5262c4e` (`test: exigir asentamientos abiertos a pie`).

```bash
cd /home/unde/zombie-survival-3d/game
godot --headless --path . res://10_review/OpenSettlementTest.tscn --quit-after 1200
```

Resultado: exit code `1`, `OPEN_SETTLEMENT_TEST failures=2`.

La puerta construyó el barrio real y detectó:

1. un `StaticBody2D` llamado `Barricade` en el asentamiento principal;
2. el cartel `CERRADO` asociado a esa barricada.

Al mismo tiempo confirmó que los tres pueblos secundarios y sus casas ya
existían; el defecto era el cierre físico del pueblo principal.

## GREEN

La GREEN elimina el cierre, no lo oculta:

- `Neighborhood.build()` ya no llama a `_build_barricade()`.
- Se elimina por completo `_build_barricade()`, incluido su `StaticBody2D`,
  su colisión, su visual y el cartel `CERRADO`.
- `_build_towns()` y los caminos peatonales permanecen intactos.

Resultado:

```text
OPEN_SETTLEMENT_TEST failures=0
```

## Garantías de la puerta

| # | Garantía | Resultado |
|---|---|---|
| 1 | El pueblo principal no conserva barricada física | PASS |
| 2 | Ningún pueblo muestra `CERRADO` | PASS |
| 3 | Existen al menos tres pueblos secundarios | PASS |
| 4 | Los pueblos secundarios conservan casas transitables | PASS |
