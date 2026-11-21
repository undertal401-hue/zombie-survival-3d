# Sprite pack de objetos — pendiente del autor

El runtime ya resuelve los iconos por rutas data-driven y los muestra en la
mano del personaje. Este directorio está vacío a propósito: **no se inventan
sprites sustitutos**.

## FALTA ASSET - NO INVENTAR

El autor debe aportar los PNG pixel-art finales en estas rutas:

- `comida.png`
- `medkit.png`
- `pistol_ammo.png`
- `rifle_ammo.png`
- `shotgun_ammo.png`
- `machete.png`
- `pistol.png`
- `shotgun.png`
- `rifle.png`
- `combustible.png`
- `scrap.png`
- `cloth.png`
- `vehicle_fuel.png`
- `llave.png`

La puerta `HeldItemVisualTest` verifica dos estados sin depender de que este
pack llegue hoy:

1. Si no existe el asset, el juego muestra exactamente
   `FALTA ASSET - NO INVENTAR` y no fabrica un bloque de color.
2. Si existe un `Texture2D` real, `HeldItem` lo muestra y oculta el marcador.

No modificar los PNG originales fuera del proyecto; las copias autorizadas se
integran en `game/assets/` mediante una revisión con hash.
