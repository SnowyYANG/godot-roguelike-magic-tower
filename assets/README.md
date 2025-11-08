Assets for roglike-magic-tower

This folder is the location for tile and sprite PNGs. The runtime script currently
creates a TileMap and TileSet from programmatically-generated 12x12 ImageTextures,
so the game runs without any files here. When you want to replace the temporary
textures with real artwork, put 12x12 PNGs here and update the script to load
those textures instead of the generated colors (see ASSET_PATHS constant).

Suggested filenames (place under res://assets/):
- floor.png
- wall.png
- stairs.png
- player.png
- item_atk.png
- item_def.png
- item_hp.png
- monster_type0_frame0.png
- monster_type0_frame1.png
- monster_type1_frame0.png
- monster_type1_frame1.png
- monster_type2_frame0.png
- monster_type2_frame1.png

Notes:
- The in-script TileSet generation will pick up these files if you modify
  `_ensure_tilemap()` to load them via `load("res://assets/filename.png")`.
- Keep each sprite 12x12 so the grid lines up with CELL = 12.
