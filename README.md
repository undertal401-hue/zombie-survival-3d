# Zombie Survival 3D

Wave-based survival en Godot 4.3 con arquitectura **ECS-lite** (composición sobre herencia),
comunicación por **EventBus** y datos en `16_data/`. Rating PEGI 16.

## Estructura (17 carpetas)

| Carpeta | Responsabilidad |
|---|---|
| `01_core` | GameManager, EventBus, Config, GameClock, ObjectPool |
| `02_player` | Controller, Stats, Inventario, Input, infección, stamina |
| `03_zombies` | BaseZombie, 8 tipos, IA, spawner con pooling, loot |
| `04_weapons` | BaseWeapon, 14 armas, proyectiles, pooling de balas |
| `05_combat` | DamageSystem, hitbox/hurtbox, sangre, knockback |
| `06_waves` | WaveManager, escalado, temporizador 8:00, fase de tienda |
| `07_house` | Generador de casa, habitaciones, pasillos, baño seguro |
| `08_ui` | HUD, barras, tienda, pausa, menús |
| `09_audio` | SFX espaciales, música, mixer |
| `10_effects` | Sangre, muzzle flash, impactos, partículas con pooling |
| `11_items` | Munición, comida, pociones, upgrades permanentes |
| `12_economy` | Monedas, tienda, precios, rarezas, tablas de botín |
| `13_save` | Guardado, checkpoints, progreso, ajustes |
| `14_debug` | Consola, profiler, cheats, gizmos, validador de escenas |
| `15_shaders` | Sangre, infección, outline, dissolve |
| `16_data` | Resources .tres de stats, curvas, localización |
| `17_tests` | Unitarias, integración, validación de escenas, `run_all.gd` |

## Comandos

```bash
# Validar el proyecto (import + parseo)
godot --headless --path game --import

# Suite completa de tests
godot --headless --path game --script 17_tests/run_all.gd

# Validación de escenas
godot --headless --path game --script 17_tests/test_scene_validation.gd -- --all

# Conteo de LOC
find game -name "*.gd" | wc -l
find game -name "*.gd" -exec wc -l {} + | tail -1
```

## Reglas de oro

- **Composition over inheritance**: cada entidad es `Node3D` + componentes (`Resource`).
- **EventBus** para toda comunicación cross-sistema; cero referencias directas entre sistemas.
- **Data-driven**: stats y curvas viven en `16_data/*.tres` / `*.csv`.
- **Object pooling** obligatorio (zombies, balas, sangre, partículas).
- Fase de compra exacta de **8:00** con `WaveTimer`.
- Baño: recarga de munición + cura de infección (−25%, 1× gratis/partida) + tienda.
- Drops raros (1–3%) otorgan mejoras **permanentes** persistidas en `SaveSystem`.
- Máximo **200 líneas por archivo**; tipado estricto; cero warnings.

## Estado del scaffolding

Ver `progress.json`.