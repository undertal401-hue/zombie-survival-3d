#!/usr/bin/env python3
"""
Divide ground_tiles.png (512x512) en tiles individuales de 32x32 o 48x48
y genera un TileSet estructurado tipo Minecraft/Terraria.
"""

from PIL import Image
import json
import os

SOURCE_DIR = "/home/unde/lumina_textures"
OUTPUT_DIR = "/home/unde/zombie-survival-3d/game/assets/ground_tiles_split"

GROUND_TILES = os.path.join(SOURCE_DIR, "ground_tiles.png")
DECORATION_TILES = os.path.join(SOURCE_DIR, "decoration_tiles.png")

# Tamaños de tile a probar
TILE_SIZES = [32, 48, 16, 64]

def analyze_atlas(image_path, tile_size):
    """Analiza el atlas y detecta tiles únicos."""
    img = Image.open(image_path)
    width, height = img.size
    
    cols = width // tile_size
    rows = height // tile_size
    
    print(f"Atlas: {width}x{height}, Tile: {tile_size}x{tile_size} -> {cols}x{rows} = {cols*rows} tiles")
    
    tiles = []
    for row in range(rows):
        for col in range(cols):
            x = col * tile_size
            y = row * tile_size
            tile = img.crop((x, y, x + tile_size, y + tile_size))
            
            # Verificar si el tile tiene contenido (no transparente total)
            has_content = False
            if tile.mode == 'RGBA':
                # Verificar si hay al menos un pixel no transparente
                for px in tile.getdata():
                    if px[3] > 0:
                        has_content = True
                        break
            else:
                has_content = True
            
            if has_content:
                tiles.append({
                    'row': row,
                    'col': col,
                    'x': x,
                    'y': y,
                    'image': tile
                })
    
    print(f"  Tiles con contenido: {len(tiles)}")
    return tiles, cols, rows

def save_tiles(tiles, output_base, tile_size):
    """Guarda cada tile como archivo PNG individual."""
    os.makedirs(output_base, exist_ok=True)
    
    manifest = {
        'tile_size': tile_size,
        'tiles': []
    }
    
    for i, tile_info in enumerate(tiles):
        filename = f"tile_{tile_info['row']:02d}_{tile_info['col']:02d}.png"
        filepath = os.path.join(output_base, filename)
        tile_info['image'].save(filepath)
        
        manifest['tiles'].append({
            'id': i,
            'filename': filename,
            'row': tile_info['row'],
            'col': tile_info['col'],
            'atlas_x': tile_info['x'],
            'atlas_y': tile_info['y']
        })
    
    # Guardar manifest
    with open(os.path.join(output_base, 'manifest.json'), 'w') as f:
        json.dump(manifest, f, indent=2)
    
    print(f"Guardados {len(tiles)} tiles en {output_base}")
    return manifest

def create_godot_tileset(manifest, output_path, texture_path):
    """Genera un archivo .tres TileSet para Godot 4."""
    tile_size = manifest['tile_size']
    
    tileset = {
        "format_version": 3,
        "resource_type": "TileSet",
        "tile_size": {"x": tile_size, "y": tile_size},
        "sources": [
            {
                "id": 0,
                "type": "TileSetAtlasSource",
                "texture": texture_path,
                "texture_region_size": {"x": tile_size, "y": tile_size},
                "tiles": {}
            }
        ]
    }
    
    for tile in manifest['tiles']:
        tileset['sources'][0]['tiles'][f"{tile['id']}"] = {
            "atlas_coords": {"x": tile['col'], "y": tile['row']}
        }
    
    with open(output_path, 'w') as f:
        json.dump(tileset, f, indent=2)
    
    print(f"TileSet guardado en {output_path}")

def main():
    print("=== Analizando ground_tiles.png ===")
    
    for tile_size in TILE_SIZES:
        tiles, cols, rows = analyze_atlas(GROUND_TILES, tile_size)
        if len(tiles) > 0:
            print(f"\n=== Tile size {tile_size}x{tile_size}: {len(tiles)} tiles válidos ===")
            output_dir = os.path.join(OUTPUT_DIR, f"ground_{tile_size}px")
            manifest = save_tiles(tiles, output_dir, tile_size)
            manifest['tile_size'] = tile_size
            manifest['cols'] = cols
            manifest['rows'] = rows
            
            # Guardar manifest con tile_size
            with open(os.path.join(output_dir, 'manifest.json'), 'w') as f:
                json.dump(manifest, f, indent=2)
            
            # Generar TileSet .tres
            tres_path = os.path.join(output_dir, f"GroundTiles_{tile_size}px.tres")
            create_godot_tileset(manifest, tres_path, f"res://assets/ground_tiles_split/ground_{tile_size}px/")
    
    print("\n=== Analizando decoration_tiles.png ===")
    for tile_size in [32, 48, 64]:
        tiles, cols, rows = analyze_atlas(DECORATION_TILES, tile_size)
        if len(tiles) > 0:
            print(f"\n=== Tile size {tile_size}x{tile_size}: {len(tiles)} tiles válidos ===")
            output_dir = os.path.join(OUTPUT_DIR, f"decoration_{tile_size}px")
            manifest = save_tiles(tiles, output_dir, tile_size)
            manifest['tile_size'] = tile_size
            with open(os.path.join(output_dir, 'manifest.json'), 'w') as f:
                json.dump(manifest, f, indent=2)

if __name__ == "__main__":
    main()