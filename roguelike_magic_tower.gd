extends Node2D

const CELL := 12
const INNER := 8
const OUTER := INNER + 2 # 11
const MAP_SIZE := OUTER

const MONSTER_TYPES := 3
const MONSTER_RATIO_BY_FLOOR = [
	[],
	[70, 30, 0],
	[60, 40, 0],
	[50, 50, 0],
	[50, 40, 10],
	[30, 50, 20],
	[20, 60, 20],
	[30, 40, 30],
	[20, 50, 30],
	[20, 40, 40],
	[0, 50, 50]
]

enum CellKind {FLOOR, WALL, MONSTER, ITEM, STAIRS}

var map = [] # 2D array [x][y] -> dictionary describing the cell

var current_floor = 1

var player = {
	"pos": Vector2(),
	"hp": 40,
	"atk": 3,
	"def": 1
}

var monster_s = {
	"type": "s",
	"hp": 6,
	"atk": 2,
	"def": 0
}

var monster_m = {
	"type": "m",
	"hp": 8,
	"atk": 3,
	"def": 1
}

var monster_l = {
	'type': 'l',
	"hp": 10,
	"atk": 4,
	"def": 2
}

var monster_dragon = {
	"type": "dragon",
	"hp": 20,
	"atk": 8,
	"def": 4
}

const RARE_DROP_RATE := 0.07

var rng := RandomNumberGenerator.new()

@onready var _tilemap : TileMapLayer = $Map
@onready var _player_sprite: Sprite2D = $Map/Player
@onready var player_sound: AudioStreamPlayer2D = $Map/Player/Sound

func _ready():
	rng.randomize()
	load_map(current_floor)
	render_tilemap()

func _process(_delta: float) -> void:
	$Control/Hp.text = str(player['hp'])
	$Control/Atk.text = str(player['atk'])
	$Control/Def.text = str(player['def'])

func _input(event):
	var dir = Vector2()
	# handle arrow keys for movement
	if event.is_action_pressed("move_up"):
		dir = Vector2(0, -1)
	elif event.is_action_pressed("move_down"):
		dir = Vector2(0, 1)
	elif event.is_action_pressed("move_left"):
		dir = Vector2(-1, 0)
	elif event.is_action_pressed("move_right"):
		dir = Vector2(1, 0)

	if dir != Vector2():
		_try_move(dir)
		render_tilemap()

func render_tilemap() -> void:
	if _tilemap == null:
		return
	for x in range(MAP_SIZE):
		for y in range(MAP_SIZE):
			var cell = map[x][y]
			var coords:Vector2i
			match cell["kind"]:
				CellKind.WALL:
					coords = Vector2i(8,3)
				CellKind.FLOOR:
					coords = Vector2i(22,0)
				CellKind.MONSTER:
					var mtype = 0
					if cell["variant"] and cell["variant"].has("type"):
						mtype = 0 if cell["variant"]["type"] == "s" else 1 if cell["variant"]["type"] == "m" else 2
					mtype = clamp(mtype, 0, MONSTER_TYPES - 1)
					coords = Vector2i(104 + mtype, 42)
				CellKind.ITEM:
					# choose tile by item type if variant exists
					var itype = cell["variant"].type
					if itype == "atk":
						coords = Vector2i(40,6)
					elif itype == "def":
						coords = Vector2i(40,12)
					else:
						coords = Vector2i(30,4)
				CellKind.STAIRS:
					coords = Vector2i(24,0)
			if y < 9 || current_floor > 1:
				_tilemap.set_cell(Vector2i(x, y), 0, coords)
	var p = player["pos"]
	_player_sprite.position = Vector2(p.x * CELL + 1, p.y * CELL + 1)

func load_map(floor):
	# initialize blank map
	var map_start = Vector2i(0 if floor >10 || rng.randf() < 0.5 else 11, (floor - 1)*11)
	map = []
	var stair_placed = false
	for x in range(MAP_SIZE):
		map.append([])
		for y in range(MAP_SIZE):
			# Copy tilemaplayer's cell at (x, y) to map
			var cell_dict = {
				"kind": CellKind.FLOOR,
				"variant": null,
				"stairs_hidden": false
			}
			var tile_coords = $StoryMaps.get_cell_atlas_coords(map_start + Vector2i(x, y))
			# You can customize mapping from tile_coords to CellKind here
			if tile_coords == Vector2i(8,3):
				cell_dict["kind"] = CellKind.WALL
			elif tile_coords == Vector2i(22,0):
				cell_dict["kind"] = CellKind.FLOOR
			elif tile_coords == Vector2i(24,0):
				cell_dict["kind"] = CellKind.STAIRS
				stair_placed = true
			elif tile_coords == Vector2i(196,1):
				cell_dict["kind"] = CellKind.FLOOR
				player['pos'] = Vector2(x, y) # set player start pos
			elif tile_coords == Vector2i(40,6):
				cell_dict["kind"] = CellKind.ITEM
				cell_dict["variant"] = {"type": "atk", "value": 1}
			elif tile_coords == Vector2i(40,12):
				cell_dict["kind"] = CellKind.ITEM
				cell_dict["variant"] = {"type": "def", "value": 1}
			elif tile_coords == Vector2i(30,4):
				cell_dict["kind"] = CellKind.ITEM
				cell_dict["variant"] = {"type": "hp", "value": 5}
			elif tile_coords.x >= 104 and tile_coords.y == 42:
				cell_dict["kind"] = CellKind.MONSTER
				cell_dict["variant"] = {"type": tile_coords.x - 104, "hp": 6, "atk": 2, "def": 0}
				var r = rng.randf() * 100
				var m
				var ratio = MONSTER_RATIO_BY_FLOOR[floor]
				if r < ratio[0]:
					m = monster_s
				elif r < ratio[0] + ratio[1]:
					m = monster_m
				else:
					m = monster_l
				cell_dict.kind = CellKind.MONSTER
				cell_dict.variant = {
					"hp": m.hp,
					"atk": m.atk,
					"def": m.def,
					"type": m.type,
					"rare_drop": (m.type == "l" and rng.randf() < RARE_DROP_RATE)
				}
			map[x].append(cell_dict)
	if !stair_placed:
		var px = int(player["pos"].x)
		var py = int(player["pos"].y)
		var placed = false
		var attempts = 0
		while !placed and attempts < 500:
			attempts += 1
			var sx = rng.randi_range(1, MAP_SIZE - 2)
			var sy = rng.randi_range(1, MAP_SIZE - 2)
			if Vector2i(sx, sy).distance_to(Vector2i(px, py)) < 3:
				continue
			var free = 0
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if map[sx + d.x][sy + d.y].kind != CellKind.WALL:
					free += 1
			if free < 3:
				continue
			var c = map[sx][sy]
			if c.kind == CellKind.WALL:
				continue
			if c.kind == CellKind.FLOOR:
				c.kind = CellKind.STAIRS
				placed = true
			else:
				c.stairs_hidden = true
				placed = true

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
		current_floor += 1
		load_map(current_floor)
		render_tilemap()
	else:
		# floor or previously cleared cell
		player["pos"] = Vector2(nx, ny)

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
	var turns = 0
	while mon_hp > 0 and player["hp"] > 0:
		# player deals damage
		var dmg = max(1, player["atk"] - mon_def)
		mon_hp -= dmg
		# monster retaliates if still alive
		if mon_hp > 0:
			var mdmg = max(1, mon_atk - player["def"])
			player["hp"] -= mdmg
		turns = turns + 1

	if player["hp"] <= 0:
		print("You were slain by the monster. (Game over placeholder)")
		# For now, reset HP so the demo can continue
		player["hp"] = 1
		return

	# Monster defeated
	print("Monster defeated by " + str(turns) + ' turn(s)!')
	# clear monster from map
	map[mx][my]["kind"] = CellKind.FLOOR
	map[mx][my]["variant"] = null

	# if stairs were hidden here, reveal them
	if map[mx][my]["stairs_hidden"]:
		map[mx][my]["kind"] = CellKind.STAIRS
		stairs_revealed()

	# move player into the cell
	player["pos"] = Vector2(mx, my)
	call_deferred("render_tilemap")

func _pickup_item(ix: int, iy: int) -> void:
	var ide = map[ix][iy]["variant"]
	if ide == null:
		map[ix][iy]["kind"] = CellKind.FLOOR
		render_tilemap()
		return

	var t = ide.get("type")
	var v = int(ide.get("value", 0))
	match t:
		"atk":
			player["atk"] += v
		"def":
			player["def"] += v
		"hp":
			player["hp"] += v

	# remove item
	map[ix][iy]["kind"] = CellKind.FLOOR
	map[ix][iy]["variant"] = null
	player_sound.stream = preload("res://assets/Fruit collect 1.wav")
	player_sound.play()

	# reveal stairs if hidden here
	if map[ix][iy]["stairs_hidden"]:
		map[ix][iy]["stairs_hidden"] = false
		map[ix][iy]["kind"] = CellKind.STAIRS
		stairs_revealed()

	# move player into the cell
	player["pos"] = Vector2(ix, iy)
	render_tilemap()

func stairs_revealed():
	$Map/Player/StairRevealedSoundplayer_sound.play()
