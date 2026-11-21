# TDD evidence — FASE 1, punto 8: pueblos abiertos a pie

## Requisito

Los pueblos deben recorrerse caminando desde el campo. No puede quedar una
barricada física ni un cartel `CERRADO` en el asentamiento principal. Los
pueblos secundarios deben seguir presentes, conservar casas propias y estar
conectados por caminos a la red principal.

## RED 1 — cierre original

Checkpoint commit: `5262c4e` (`test: exigir asentamientos abiertos a pie`).

```bash
cd /home/unde/zombie-survival-3d/game
godot --headless --path . --import
godot --headless --path . res://10_review/OpenSettlementTest.tscn --quit-after 1200
```

Resultado: exit code `1`, `OPEN_SETTLEMENT_TEST failures=2`.

La puerta construyó el barrio real y detectó:

1. un `StaticBody2D` llamado `Barricade` en el asentamiento principal;
2. el cartel `CERRADO` asociado a esa barricada.

Al mismo tiempo confirmó que los tres pueblos secundarios y sus casas ya
existían; el defecto era el cierre físico del pueblo principal.

## RED 2 — revisión independiente

Checkpoint commit: `e86b3ca` (`test: exigir rutas reales hacia los pueblos`).

La revisión mostró que contar etiquetas y casas podía dar verde aunque:

- un hueco perimetral estuviera cerrado;
- una barrera tuviera otro nombre;
- los caminos de conexión de los pueblos fueran eliminados.

La puerta endurecida carga ahora `Main.tscn`, usa el navmesh real y exige un
travesía por cada hueco norte, oeste y sur. También exige una geometria de
conexión identificada para cada pueblo.

Resultado: exit code `1`, `OPEN_SETTLEMENT_TEST failures=3`. Los tres fallos
fueron los centros semánticos de pueblo que la implementación todavía no
expulsaba.

## RED 3 — corredores ocupados

Checkpoint commit: `8caca70` (`test: exigir corredores peatonales sin casas`).

La prueba reforzada mostró que una casa procedural puede ocupar el hueco sur
y cerrar la única ruta local. Resultado: exit code `1`,
`OPEN_SETTLEMENT_TEST failures=1`:

```text
FAIL Ninguna casa bloquea los tres corredores de acceso peatonal
```

## GREEN

La GREEN corrige el comportamiento, no solamente la aserción:

- `Neighborhood.build()` ya no llama a `_build_barricade()`.
- Se elimina por completo `_build_barricade()`, incluido su `StaticBody2D`,
  su colisión, su visual y el cartel `CERRADO`.
- `Main._configure_wall()` calcula el hueco sobre el eje correcto del muro.
  Antes confundía X con Y en muros horizontales y Y con X en verticales; los
  tres pasos anunciados no coincidían con las colisiones reales.
- `Neighborhood` reserva las celdas de los corredores norte, oeste y sur para
  que ninguna casa procedural pueda cerrar una entrada.
- Cada pueblo conserva un claro central y sus casas se colocan a partir de
  ese claro.
- Cada etiqueta de pueblo expone su centro mediante el metadato
  `town_center` y cada conector se identifica como `TownPath_<pueblo>`.
- `_connect_town_to_road()` usa la constante global `INF` e `is_finite()`.
  En Godot 4.7, `float("inf")` devuelve `0.0`; la comparación anterior
  `best_dist < float("inf")` era falsa y **no creaba ningún camino**.
- `QA.gd` ya no excluye artificialmente un futuro nodo llamado `Barricade`
  de la inspección de props.

Resultado actual:

```text
OPEN_SETTLEMENT_TEST failures=0
```

La puerta se ejecutó **30/30 veces** con posiciones y casas procedurales
diferentes, sin flakes.

## Garantías de la puerta

| # | Garantía | Resultado |
|---|---|---|
| 1 | Ningún pueblo muestra `CERRADO` | PASS |
| 2 | Ninguna casa bloquea los tres corredores peatonales | PASS |
| 3 | Se puede cruzar caminando el hueco norte, oeste y sur | PASS |
| 4 | Cada pueblo conserva etiqueta, centro y casas propias | PASS |
| 5 | Cada pueblo conserva un camino identificado | PASS |
| 6 | El camino de cada pueblo alcanza su centro | PASS |
| 7 | El camino de cada pueblo toca una carretera principal | PASS |
| 8 | El centro de cada pueblo pertenece a una zona navegable | PASS |

## Nota de reproducibilidad

En un checkout limpio se debe ejecutar primero `godot --headless --path
game --import`; sin la caché de clases globales, Godot puede terminar antes de
ejecutar las aserciones. CI ya realiza ese import antes de las suites.
