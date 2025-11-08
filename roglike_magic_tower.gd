extends Node2D

# Roglike Magic Tower - single-file core logic
# - Map is always 9x9 playable cells surrounded by a 1-cell outer wall -> 11x11 total
# - Each cell is visually represented at CELL x CELL pixels (default 12x12)
# - This script generates walls, monsters, items, player start and stairs
# - Stairs may be placed on a monster or item; in that case they are hidden until
#   the monster is defeated or the item picked up. Stairs never spawn on obstacles.
# - Assets are optional; the script draws a simple colored fallback (so it runs
#   without any imported sprites). To use textures, set the texture paths below.

const CELL := 12
const INNER := 9
const OUTER := INNER + 2 # 11
const MAP_SIZE := OUTER

const MONSTER_TYPES := 3
const MONSTER_ANIM_INTERVAL := 0.45

var _monster_anim_phase := 0 # 0 or 1
var _monster_anim_timer := 0.0

# per-type two-frame colors for fallback drawing (replace with sprite frames when available)
const MONSTER_FRAME_COLORS = [
	[Color(1.0, 0.45, 0.45), Color(1.0, 0.6, 0.6)],
	[Color(0.9, 0.75, 0.35), Color(1.0, 0.85, 0.45)],
	[Color(0.7, 0.5, 1.0), Color(0.85, 0.7, 1.0)]
]

enum CellKind {FLOOR, WALL, MONSTER, ITEM, STAIRS}

var map = [] # 2D array [x][y] -> dictionary describing the cell

var player = {
	"pos": Vector2(),
	"hp": 100,
	"atk": 10,
	"def": 3
}

var rng := RandomNumberGenerator.new()

var _tilemap : TileMapLayer = null
var _tileset : TileSet = null
var _tile_ids = {}

func _create_tex_from_color(c: Color) -> Texture:
	var img = Image.create(CELL, CELL, false, Image.FORMAT_RGBA8)
	for px in range(CELL):
		for py in range(CELL):
			img.set_pixel(px, py, c)
	var it = ImageTexture.create_from_image(img)
	return it

func _add_tile_to_tileset(ts: TileSet, id: int, tile_name: String, tex: Texture) -> void:
	var pattern: TileMapPattern = TileMapPattern.new()
	pattern.set_size(Vector2i(CELL, CELL))
	ts.add_pattern(pattern, id)
	_tile_ids[tile_name] = id

# Optional texture paths (adjust when you import assets). If textures are missing the
# script falls back to drawing colored rects.
const ASSET_PATHS = {
	"floor": "res://sprites/floor.png",
	"wall": "res://sprites/wall.png",
	"monster": "res://sprites/monster.png",
	"item_atk": "res://sprites/item_atk.png",
	"item_def": "res://sprites/item_def.png",
	"item_hp": "res://sprites/item_hp.png",
	"stairs": "res://sprites/stairs.png",
	"player": "res://sprites/player.png"
}

func _ready():
	rng.randomize()
	_init_map()
	# ensure runtime TileMap (uses programmatic ImageTextures sized CELL x CELL)
	# d_ensure_tilemap()
	# render initial map into TileMap
	call_deferred("_render_tilemap")

	# Print a small help so the user knows controls
	print("Magic Tower: use arrow keys to move. Fight monsters by moving into them. Pick items by moving onto them. Stairs appear after killing a monster or picking an item if hidden.")

func _process(delta: float) -> void:
	# advance monster animation timer; flip global phase every interval
	_monster_anim_timer += delta
	if _monster_anim_timer >= MONSTER_ANIM_INTERVAL:
		_monster_anim_timer = 0.0
		_monster_anim_phase = 1 - _monster_anim_phase
		call_deferred("_render_tilemap")


func _ensure_tilemap() -> void:
	# create TileMap and TileSet at runtime. This allows immediate TileMap rendering
	# without requiring pre-created TileSet resources. Textures are generated from
	# Image objects sized CELL x CELL so they match your pixel grid.
	if _tilemap != null:
		return

	_tilemap = TileMapLayer.new()
	add_child(_tilemap)

	_tileset = TileSet.new()
	_tileset.tile_size = Vector2i(CELL, CELL)
	var next_id = 0

	# floor and wall
	_add_tile_to_tileset(_tileset, next_id, "floor", _create_tex_from_color(Color(0.95, 0.95, 0.9)))
	next_id += 1
	_add_tile_to_tileset(_tileset, next_id, "wall", _create_tex_from_color(Color(0.2, 0.2, 0.2)))
	next_id += 1
	_add_tile_to_tileset(_tileset, next_id, "stairs", _create_tex_from_color(Color(0.5, 0.75, 1.0)))
	next_id += 1

	# items
	_add_tile_to_tileset(_tileset, next_id, "item_atk", _create_tex_from_color(Color(0.6, 0.9, 0.6)))
	next_id += 1
	_add_tile_to_tileset(_tileset, next_id, "item_def", _create_tex_from_color(Color(0.5, 0.85, 0.5)))
	next_id += 1
	_add_tile_to_tileset(_tileset, next_id, "item_hp", _create_tex_from_color(Color(0.4, 1.0, 0.6)))
	next_id += 1

	# monsters: type/frame combinations
	for t in range(MONSTER_TYPES):
		for f in range(2):
			var col = MONSTER_FRAME_COLORS[t][f]
			_add_tile_to_tileset(_tileset, next_id, "monster_%d_%d" % [t, f], _create_tex_from_color(col))
			next_id += 1

	# player
	_add_tile_to_tileset(_tileset, next_id, "player", _create_tex_from_color(Color(1.0, 1.0, 0.1)))
	next_id += 1

	_tilemap.tile_set = _tileset


func _render_tilemap() -> void:
	if _tilemap == null:
		return
	# Clear all existing cells
	for x in range(MAP_SIZE):
		for y in range(MAP_SIZE):
			_tilemap.set_cell(Vector2i(x, y))

	# Fill according to map
	for x in range(MAP_SIZE):
		for y in range(MAP_SIZE):
			var cell = map[x][y]
			var tid = -1
			match cell["kind"]:
				CellKind.WALL:
					tid = _tile_ids.get("wall", -1)
				CellKind.FLOOR:
					tid = _tile_ids.get("floor", -1)
				CellKind.MONSTER:
					var mtype = 0
					if cell["variant"] and cell["variant"].has("type"):
						mtype = int(cell["variant"]["type"])
					mtype = clamp(mtype, 0, MONSTER_TYPES - 1)
					var frame = _monster_anim_phase
					tid = _tile_ids.get("monster_%d_%d" % [mtype, frame], -1)
				CellKind.ITEM:
					# choose tile by item type if variant exists
					var itype = cell["variant"].type
					if itype == "atk":
						tid = _tile_ids.get("item_atk", -1)
					elif itype == "def":
						tid = _tile_ids.get("item_def", -1)
					else:
						tid = _tile_ids.get("item_hp", -1)
				CellKind.STAIRS:
					tid = _tile_ids.get("stairs", -1)

			if tid >= 0:
				_tilemap.set_cell(Vector2i(x, y), tid)

	# draw player on top by setting its tile
	var p = player["pos"]
	var ptid = _tile_ids.get("player", -1)
	if ptid >= 0:
		_tilemap.set_cell(Vector2i(int(p.x), int(p.y)), ptid)

func _init_map():
	# initialize blank map
	map = []
	for x in range(MAP_SIZE):
		map.append([])
		for y in range(MAP_SIZE):
			var cell = {
				"kind": CellKind.FLOOR,
				"variant": null, # monster/item data
				"has_stairs": false,
				"stairs_hidden": false
			}
			# outer walls
			if x == 0 or y == 0 or x == MAP_SIZE - 1 or y == MAP_SIZE - 1:
				cell["kind"] = CellKind.WALL
			map[x].append(cell)

	# Randomly place inner obstacles, monsters, and items
	# Probabilities can be tuned
	var prob_wall = 0.12
	var prob_monster = 0.10
	var prob_item = 0.04

	for x in range(1, MAP_SIZE - 1):
		for y in range(1, MAP_SIZE - 1):
			var r = rng.randf()
			if r < prob_wall:
				map[x][y]["kind"] = CellKind.WALL
			else:
				# floor by default; maybe place monster or item
				var r2 = rng.randf()
				if r2 < prob_monster:
					map[x][y]["kind"] = CellKind.MONSTER
					# simple monster stats
					map[x][y]["variant"] = {
						"hp": 6 + rng.randi_range(0, 8),
						"atk": 2 + rng.randi_range(0, 3),
						"def": 0,
						"type": rng.randi_range(0, MONSTER_TYPES - 1)
					}
				elif r2 < prob_monster + prob_item:
					map[x][y]["kind"] = CellKind.ITEM
					var t = rng.randi_range(0, 2)
					match t:
						0:
							map[x][y]["variant"] = {"type": "atk", "value": 2}
						1:
							map[x][y]["variant"] = {"type": "def", "value": 1}
						2:
							map[x][y]["variant"] = {"type": "hp", "value": 8}

	# Place stairs: choose any non-wall cell. If the chosen cell currently has a
	# monster or item, mark the stairs as hidden until that content is cleared.
	var stairs_placed := false
	while not stairs_placed:
		var sx = rng.randi_range(1, MAP_SIZE - 2)
		var sy = rng.randi_range(1, MAP_SIZE - 2)
		var c = map[sx][sy]
		if c["kind"] == CellKind.WALL:
			continue
		c["has_stairs"] = true
		if c["kind"] == CellKind.MONSTER or c["kind"] == CellKind.ITEM:
			c["stairs_hidden"] = true
			# keep the cell kind as-is (monster/item) until cleared
		else:
			c["kind"] = CellKind.STAIRS
		stairs_placed = true

	# Place player start on a random floor cell (not wall, not monster/item/stairs hidden)
	var placed := false
	while not placed:
		var px = rng.randi_range(1, MAP_SIZE - 2)
		var py = rng.randi_range(1, MAP_SIZE - 2)
		var pc = map[px][py]
		if pc["kind"] == CellKind.FLOOR and not pc["has_stairs"]:
			player["pos"] = Vector2(px, py)
			placed = true

func _unhandled_input(event):
	# handle arrow keys for movement
	if event is InputEventKey and event.pressed and not event.echo:
		print("input")
		var dir = Vector2()
		if event.keycode == KEY_UP:
			dir = Vector2(0, -1)
		elif event.keycode == KEY_DOWN:
			dir = Vector2(0, 1)
		elif event.keycode == KEY_LEFT:
			dir = Vector2(-1, 0)
		elif event.keycode == KEY_RIGHT:
			dir = Vector2(1, 0)

		if dir != Vector2():
			_try_move(dir)

func _try_move(dir: Vector2) -> void:
	var nx = int(player["pos"].x + dir.x)
	var ny = int(player["pos"].y + dir.y)
	if nx < 0 or ny < 0 or nx >= MAP_SIZE or ny >= MAP_SIZE:
		return
	var target = map[nx][ny]
	if target["kind"] == CellKind.WALL:
		# blocked
		return
	elif target["kind"] == CellKind.MONSTER:
		_combat(nx, ny)
		return
	elif target["kind"] == CellKind.ITEM:
		_pickup_item(nx, ny)
		return
	elif target["kind"] == CellKind.STAIRS:
		# step on stairs (level up placeholder)
		player["pos"] = Vector2(nx, ny)
		print("You step onto the stairs. (Level up / floor change would occur here.)")
	else:
		# floor or previously cleared cell
		player["pos"] = Vector2(nx, ny)

	queue_redraw()

func _combat(mx: int, my: int) -> void:
	var mdata = map[mx][my]["variant"]
	if mdata == null:
		# safety: convert to floor
		map[mx][my]["kind"] = CellKind.FLOOR
		call_deferred("_render_tilemap")
		return

	var mon_hp = int(mdata["hp"])
	var mon_atk = int(mdata.get("atk", 1))
	var mon_def = int(mdata.get("def", 0))

	# Simple turn-based exchange until one side dies
	while mon_hp > 0 and player["hp"] > 0:
		# player deals damage
		var dmg = max(1, player["atk"] - mon_def)
		mon_hp -= dmg
		# monster retaliates if still alive
		if mon_hp > 0:
			var mdmg = max(1, mon_atk - player["def"])
			player["hp"] -= mdmg

	if player["hp"] <= 0:
		print("You were slain by the monster. (Game over placeholder)")
		# For now, reset HP so the demo can continue
		player["hp"] = 1
		return

	# Monster defeated
	print("Monster defeated!")
	# clear monster from map
	map[mx][my]["kind"] = CellKind.FLOOR
	map[mx][my]["variant"] = null

	# if stairs were hidden here, reveal them
	if map[mx][my]["has_stairs"] and map[mx][my]["stairs_hidden"]:
		map[mx][my]["stairs_hidden"] = false
		map[mx][my]["has_stairs"] = false
		map[mx][my]["kind"] = CellKind.STAIRS
		print("Stairs revealed!")

	# move player into the cell
	player["pos"] = Vector2(mx, my)
	call_deferred("_render_tilemap")

func _pickup_item(ix: int, iy: int) -> void:
	var ide = map[ix][iy]["variant"]
	if ide == null:
		map[ix][iy]["kind"] = CellKind.FLOOR
		call_deferred("_render_tilemap")
		return

	var t = ide.get("type")
	var v = int(ide.get("value", 0))
	match t:
		"atk":
			player["atk"] += v
			print("Picked up ATK +%d" % v)
		"def":
			player["def"] += v
			print("Picked up DEF +%d" % v)
		"hp":
			player["hp"] += v
			print("Picked up HP +%d" % v)

	# remove item
	map[ix][iy]["kind"] = CellKind.FLOOR
	map[ix][iy]["variant"] = null

	# reveal stairs if hidden here
	if map[ix][iy]["has_stairs"] and map[ix][iy]["stairs_hidden"]:
		map[ix][iy]["stairs_hidden"] = false
		map[ix][iy]["has_stairs"] = false
		map[ix][iy]["kind"] = CellKind.STAIRS
		print("Stairs revealed!")

	# move player into the cell
	player["pos"] = Vector2(ix, iy)
	call_deferred("_render_tilemap")

func _draw():
	# fallback drawing only when TileMap is not available (so we can run
	# without assets or TileMap). If a runtime TileMap was created we skip
	# this draw to avoid double-rendering.
	if _tilemap != null:
		return

	draw_rect(Rect2(0, 0, MAP_SIZE * CELL, MAP_SIZE * CELL), Color(0, 0, 0))
	# draw the entire map using simple colored rectangles.
	for x in range(MAP_SIZE):
		for y in range(MAP_SIZE):
			var cell = map[x][y]
			var color = Color(0.2, 0.2, 0.2) # default wall-like
			match cell["kind"]:
				CellKind.WALL:
					color = Color(0.2, 0.2, 0.2)
				CellKind.FLOOR:
					color = Color(0.95, 0.95, 0.9)
				CellKind.MONSTER:
					# monster color depends on its type and current animation phase
					var mtype = 0
					if cell["variant"] and cell["variant"].has("type"):
						mtype = int(cell["variant"]["type"])
					mtype = clamp(mtype, 0, MONSTER_TYPES - 1)
					color = MONSTER_FRAME_COLORS[mtype][_monster_anim_phase]
				CellKind.ITEM:
					color = Color(0.5, 1.0, 0.6)
				CellKind.STAIRS:
					color = Color(0.5, 0.75, 1.0)

			# if stairs are hidden at a monster/item cell, draw that underlying type
			if cell["has_stairs"] and cell["stairs_hidden"]:
				if cell["kind"] == CellKind.MONSTER:
					color = Color(1.0, 0.45, 0.45)
				elif cell["kind"] == CellKind.ITEM:
					color = Color(0.5, 1.0, 0.6)

			var rect = Rect2(x * CELL, y * CELL, CELL, CELL)
			draw_rect(rect, color)
			# border
			draw_rect(rect, Color(0, 0, 0), false, 1)

	# draw player as a yellow square
	var p = player["pos"]
	var prect = Rect2(p.x * CELL + 1, p.y * CELL + 1, CELL - 2, CELL - 2)
	draw_rect(prect, Color(1.0, 1.0, 0.1))

	# Add textual info via print() so it's visible in the debugger console
	print("HP:%d  ATK:%d  DEF:%d  Pos:(%d,%d)" % [player["hp"], player["atk"], player["def"], int(p.x), int(p.y)])
