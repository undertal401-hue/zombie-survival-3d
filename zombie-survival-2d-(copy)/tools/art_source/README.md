# Fuente de arte del skin del zombi

## `zoimbie1_hold.png`

- **Qué es**: el sprite cenital de zombi (35×43 px, 235 colores, con
  transparencia) entregado por el autor en la carpeta de Descargas. Procede del
  build Unity de `this-world-definitely-need-a-hero-but-you-are-just-a-spear`
  y es la **única** `Texture2D`/`Sprite` de zombi que contiene ese juego.
- **SHA-256**: `61df3e84c18409b698b56273a0bd014f86a23dc5622380d5d10b82124afff84e`.
  `tools/gen_zombie_skin.py` lo fija: si el fichero cambia, `--check` falla.
- **Quién lo consume**: `tools/gen_zombie_skin.py` lo deriva al pack canónico
  (`assets/enemies/zombie/`, 33 frames + 8 strips). Nada más lo usa en runtime:
  el juego carga el pack, no este PNG.
- **Por qué está aquí y no en `assets/enemies/zombie/`**: `skin_pack.py check`
  rechaza cualquier PNG que no forme parte del pack. La fuente vive fuera del
  pack para que la puerta siga siendo estricta.
- **Por qué `.gdignore`**: el fichero es entrada del generador, no un recurso
  de Godot. Con `.gdignore` el motor no lo importa ni genera artefactos; el
  test lo lee como bytes (`FileAccess.get_file_as_bytes`) y lo decodifica con
  `Image.load_png_from_buffer`.

## Procedencia y alcance

El asset es del juego original y **no se relicencia**: sigue siendo propiedad
de su autor. Se usa aquí porque el usuario lo entregó y pidió expresamente
que su zombi usara esa textura. No se reutilice fuera de este proyecto sin
permiso. La decisión y sus alternativas están en
`docs/adr/0007-zombie-skin-derived-from-real-sprite.md`.

## Carpeta reutilizable

Los frames derivados que consume el juego están en
`game/assets/enemies/zombie/`: `<anim>/<anim>_NN.png` (celda 64×64) y
`<anim>_strip.png` (celda N en `x = N * 64`). Para reconstruir el pack desde
esta fuente:

```
python3 tools/gen_zombie_skin.py           # regenera frames y strips
python3 tools/gen_zombie_skin.py --check   # verifica sin escribir
```
