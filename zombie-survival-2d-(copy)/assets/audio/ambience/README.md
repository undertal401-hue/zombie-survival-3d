# Ambiente externo (opcional)

## Incluido: `rain.ogg`

Loop real de lluvia de 19 s (44.1 kHz, mono, Vorbis q6). Fuente:
[“Rain against the window” de Nirmal Dulal, Wikimedia Commons](https://commons.wikimedia.org/wiki/File:Rain_against_the_window.ogg),
**dominio público**. Se recortó un fragmento limpio y se cruzfadeó la cola con
el principio (0,75 s) para que no haya clic al repetir. No es ruido sintético.

Coloca otros archivos **OGG o WAV** con nombres exactos para sustituir la síntesis procedural por audio real de alta calidad:

| Archivo | Uso | Duración recomendada |
|---------|-----|---------------------|
| `rain.ogg` | Lluvia / tormenta | 10–30 s (loop sin costuras) |
| `wind.ogg` | Viento / niebla | 10–30 s |
| `night.ogg` | Ambiente nocturno (grillos, etc.) | 15–40 s |
| `forest.ogg` | Bosque (pájaros, hojas) | 15–40 s |
| `tension.ogg` | Tensión / combate cercano | 8–20 s |

## Fuentes recomendadas (CC0 / gratis)

- **Freesound** (gratis con login): busca "rain loop", "forest ambience", "wind trees"
- **SFXMint Nature & Ambient** (CC0): 574 sonidos lluvia/viento/bosque
- **Kenney Audio** (CC0): packs de ambiente
- **OpenGameArt** → Audio → Ambience

## Cómo funciona

El `AudioDirector` busca estos archivos en `_ready()`:
1. Primero `res://assets/audio/ambience/rain.ogg`
2. Si no existe, `rain.wav`
3. Si no hay archivo, usa la síntesis procedural original (determinista, seed 20261117)

Los archivos **deben ser loops sin costuras** (el final encaja con el principio). Godot los reproduce en `AudioStreamPlayer` con `stream.loop = true` en el bus `AudioDirectorAmbience`.

## Volumen

Controlado por `ambience_volume` (export 0.0–1.0, default 0.6) en el inspector del `AudioDirector`.