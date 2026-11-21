# TDD evidence — FASE 1, punto 8: pueblos abiertos a pie

## Requisito

Los pueblos deben recorrerse caminando desde el campo. No puede quedar una
barricada física ni un cartel `CERRADO` en el asentamiento principal. Los
pueblos secundarios deben seguir presentes, conservar casas propias, mantener
libre su plaza central y estar conectados por una ruta navegable a la red
principal.

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

## RED 2 — rutas reales y huecos perimetrales

Checkpoint commit: `e86b3ca` (`test: exigir rutas reales hacia los pueblos`).

La revisión mostró que contar etiquetas y casas podía dar verde aunque:

- un hueco perimetral estuviera cerrado;
- una barrera tuviera otro nombre;
- los caminos de conexión de los pueblos fueran eliminados.

La puerta endurecida carga ahora `Main.tscn`, usa el navmesh real y exige una
travesía por cada hueco norte, oeste y sur. También exige una geometria de
conexión identificada para cada pueblo.

Una ejecución limpia del checkpoint dio exit code `1` y
`OPEN_SETTLEMENT_TEST failures=4`: falló el hueco sur y los tres pueblos
carecían todavía de una posición central semántica.

## RED 3 — corredores ocupados

Checkpoint commit: `8caca70` (`test: exigir corredores peatonales sin casas`).

La prueba reforzada mostró que una casa procedural puede ocupar un corredor
perimetral y cerrar la ruta local. En una ejecución limpia se obtuvo exit
code `1` y `OPEN_SETTLEMENT_TEST failures=5`: falló el corredor occupancy,
el hueco sur de esa semilla y los tres centros semánticos. El número exacto
de fallos de acceso depende de la posición procedural de las casas; la
garantía de corredor se mantuvo siempre activa.

## RED 4 — plazas bloqueadas y conectividad real

Checkpoint commit: `b63c360` (`test: exigir centros de pueblo conectados`).

La segunda revisión encontró un defecto de producción que la puerta anterior
no detectaba: los tres centros de pueblo coincidían con celdas de la rejilla
y podían quedar dentro de una casa ordinaria. Además, comprobar solamente
`map_get_closest_point()` podía dar verde a una isla del navmesh desconectada
de la red principal.

La puerta endurecida exige ahora:

- un claro público de `240x180` sin ninguna casa de rejilla o de anillo;
- un centro dentro de una zona navegable real;
- una ruta desde la red principal hasta cada centro;
- ausencia del `StaticBody2D` heredado `Barricade` y de barreras semánticas
  marcadas con el grupo o metadato `settlement_barrier`.

Resultado: exit code `1` y, como mínimo, estos tres fallos estables:

```text
FAIL El centro de Pueblo Norte permanece libre de casas
FAIL El centro de Pueblo Sur permanece libre de casas
FAIL El centro de Pueblo Oeste permanece libre de casas
```

El total exacto puede subir entre semillas porque las aserciones de ruta
también dependen de la generación procedural. En 10 ejecuciones limpias de
`b63c360` el total observado varió entre 3 y 5, pero las tres plazas
bloqueadas siempre se reprodujeron. Eso basta para probar el defecto de
producción que motivó el GREEN.

## GREEN

### Cierre físico y conectores

- `Neighborhood.build()` ya no llama a `_build_barricade()`.
- Se elimina por completo `_build_barricade()`, incluido su `StaticBody2D`,
  su colisión, su visual y el cartel `CERRADO`.
- `Neighborhood` reserva las celdas de los corredores norte, oeste y sur para
  que ninguna casa procedural pueda cerrar una entrada.
- Cada etiqueta de pueblo expone su centro mediante el metadato
  `town_center` y cada conector se identifica como `TownPath_<pueblo>`.
- `_connect_town_to_road()` usa la constante global `INF` e `is_finite()`.
  En Godot 4.7, `float("inf")` devuelve `0.0`; la comparación anterior
  `best_dist < float("inf")` era falsa y **no creaba ningún camino**.
- `QA.gd` ya no excluye artificialmente un futuro nodo llamado `Barricade`
  de la inspección de props.

`Main._configure_wall()` ya calculaba el hueco sobre el eje correcto antes de
esta fase; el commit `47c0d5e` solo añadió un comentario explicativo. No se
presenta ese cambio como una corrección de producción.

### Plazas y rutas de los pueblos

Checkpoint final: `de88f91` (`fix: reservar las plazas de los pueblos`).

- Los tres centros se derivan de las dimensiones reales del mapa.
- Una casa de la rejilla se descarta si su rectángulo invade el claro público
  de cualquier pueblo; una casa no llega a instanciarse ni a la colisión.
- Las casas de anillo calculan su radio para quedar fuera del mismo claro.
- El test ya no usa la pertenencia a una isla aislada como prueba de
  conectividad: exige una ruta del navmesh desde la red principal.

Resultado actual:

```text
OPEN_SETTLEMENT_TEST failures=0
```

La puerta final se ejecutó **50/50 veces** con posiciones y casas procedurales
diferentes, sin flakes.

## Garantías de la puerta

| # | Garantía | Resultado |
|---|---|---|
| 1 | Ningún pueblo muestra `CERRADO` | PASS |
| 2 | No existe la barricada física heredada ni una barrera semántica | PASS |
| 3 | Ninguna casa bloquea los tres corredores de acceso peatonal | PASS |
| 4 | Se puede cruzar caminando el hueco norte, oeste y sur | PASS |
| 5 | Cada pueblo conserva etiqueta, centro y casas propias | PASS |
| 6 | El claro público de cada centro no contiene casas | PASS |
| 7 | Cada pueblo conserva un camino identificado | PASS |
| 8 | El camino de cada pueblo alcanza su centro | PASS |
| 9 | El camino de cada pueblo toca una carretera principal | PASS |
| 10 | El centro de cada pueblo pertenece a una zona navegable | PASS |
| 11 | Existe una ruta real desde la red principal a cada centro | PASS |

## Nota de reproducibilidad

En un checkout limpio se debe ejecutar primero `godot --headless --path
game --import`; sin la caché de clases globales, Godot puede terminar antes de
ejecutar las aserciones. CI ya realiza ese import antes de las suites.
