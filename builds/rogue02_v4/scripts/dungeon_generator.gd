class_name DungeonGenerator
extends RefCounted

const GameState = preload("res://scripts/game_state.gd")
const Enemy = preload("res://scripts/enemy.gd")

enum TileType {
	WALL,
	FLOOR,
	ENTRANCE,
	EXIT,
	CHEST,
	ALTAR
}

class Room:
	var id: int
	var rect: Rect2i
	var center: Vector2i
	var is_entrance: bool = false
	var is_exit: bool = false
	var is_hub: bool = false
	var is_secret: bool = false
	var connections: Array[int] = []

	func _init(p_id: int, p_rect: Rect2i) -> void:
		id = p_id
		rect = p_rect
		center = Vector2i(rect.position.x + rect.size.x / 2, rect.position.y + rect.size.y / 2)

var width: int = 45
var height: int = 30
var grid: Array = []
var rooms: Array[Room] = []
var entrance_pos: Vector2i = Vector2i.ZERO
var exit_pos: Vector2i = Vector2i.ZERO
var chests: Array[Vector2i] = []
var altars: Array[Vector2i] = []
var enemies: Array[Enemy] = []
var game_state: GameState = null

func _init(p_game_state: GameState) -> void:
	game_state = p_game_state

func generate_floor(floor_num: int) -> void:
	rooms.clear()
	chests.clear()
	altars.clear()
	enemies.clear()

	grid.resize(width)
	for x in range(width):
		grid[x] = []
		grid[x].resize(height)
		for y in range(height):
			grid[x][y] = TileType.WALL

	var num_rooms_target: int = game_state.randi_range(6, 8)
	var attempts: int = 0
	while rooms.size() < num_rooms_target and attempts < 100:
		attempts += 1
		var rw: int = game_state.randi_range(5, 9)
		var rh: int = game_state.randi_range(5, 11)
		var rx: int = game_state.randi_range(2, width - rw - 3)
		var ry: int = game_state.randi_range(2, height - rh - 3)
		var new_rect: Rect2i = Rect2i(rx, ry, rw, rh)

		var overlaps: bool = false
		for r in rooms:
			var expanded: Rect2i = r.rect.grow(2)
			if expanded.intersects(new_rect):
				overlaps = true
				break

		if not overlaps:
			var room_obj: Room = Room.new(rooms.size(), new_rect)
			rooms.append(room_obj)

	if rooms.size() < 4:
		rooms.clear()
		rooms.append(Room.new(0, Rect2i(3, 3, 7, 7)))
		rooms.append(Room.new(1, Rect2i(18, 10, 9, 9)))
		rooms.append(Room.new(2, Rect2i(32, 4, 7, 8)))
		rooms.append(Room.new(3, Rect2i(31, 18, 8, 8)))

	rooms[0].is_entrance = true
	rooms[rooms.size() - 1].is_exit = true

	var max_area: int = -1
	var hub_idx: int = 1
	for i in range(rooms.size()):
		var area: int = rooms[i].rect.size.x * rooms[i].rect.size.y
		if area > max_area and not rooms[i].is_entrance and not rooms[i].is_exit:
			max_area = area
			hub_idx = i
	rooms[hub_idx].is_hub = true

	var secret_idx: int = -1
	for i in range(rooms.size()):
		if not rooms[i].is_entrance and not rooms[i].is_exit and not rooms[i].is_hub:
			secret_idx = i
			break
	if secret_idx == -1 and rooms.size() > 2:
		secret_idx = 1
	if secret_idx != -1:
		rooms[secret_idx].is_secret = true

	for r in rooms:
		for x in range(r.rect.position.x, r.rect.position.x + r.rect.size.x):
			for y in range(r.rect.position.y, r.rect.position.y + r.rect.size.y):
				grid[x][y] = TileType.FLOOR

	_connect_rooms()

	entrance_pos = rooms[0].center
	grid[entrance_pos.x][entrance_pos.y] = TileType.ENTRANCE

	var exit_room: Room = rooms[rooms.size() - 1]
	exit_pos = exit_room.center
	grid[exit_pos.x][exit_pos.y] = TileType.EXIT

	if GameState.CHEST_FLOORS.has(floor_num):
		for r in rooms:
			if r.is_secret:
				var chest_pos: Vector2i = r.center
				grid[chest_pos.x][chest_pos.y] = TileType.CHEST
				chests.append(chest_pos)
				break

	if GameState.ALTAR_FLOORS.has(floor_num):
		var hub_altar: Vector2i = rooms[hub_idx].center
		if hub_altar != entrance_pos and hub_altar != exit_pos:
			grid[hub_altar.x][hub_altar.y] = TileType.ALTAR
			altars.append(hub_altar)

	_spawn_enemies(floor_num)

func _connect_rooms() -> void:
	var connected: Array[int] = [0]
	var unconnected: Array[int] = []
	for i in range(1, rooms.size()):
		unconnected.append(i)

	while unconnected.size() > 0:
		var best_dist: float = 1e9
		var best_c: int = -1
		var best_u: int = -1

		for c in connected:
			for u in unconnected:
				var d: float = rooms[c].center.distance_to(rooms[u].center)
				if d < best_dist:
					best_dist = d
					best_c = c
					best_u = u

		_carve_corridor(rooms[best_c].center, rooms[best_u].center)
		rooms[best_c].connections.append(best_u)
		rooms[best_u].connections.append(best_c)
		connected.append(best_u)
		unconnected.erase(best_u)

	if rooms.size() >= 4:
		var r1: int = game_state.randi_range(1, rooms.size() - 1)
		var r2: int = game_state.randi_range(1, rooms.size() - 1)
		if r1 != r2 and not rooms[r1].connections.has(r2):
			_carve_corridor(rooms[r1].center, rooms[r2].center)
			rooms[r1].connections.append(r2)
			rooms[r2].connections.append(r1)

func _carve_corridor(from: Vector2i, to: Vector2i) -> void:
	var cur: Vector2i = from
	var coin: bool = game_state.randf() < 0.5

	if coin:
		while cur.x != to.x:
			grid[cur.x][cur.y] = TileType.FLOOR
			cur.x += 1 if to.x > cur.x else -1
		while cur.y != to.y:
			grid[cur.x][cur.y] = TileType.FLOOR
			cur.y += 1 if to.y > cur.y else -1
	else:
		while cur.y != to.y:
			grid[cur.x][cur.y] = TileType.FLOOR
			cur.y += 1 if to.y > cur.y else -1
		while cur.x != to.x:
			grid[cur.x][cur.y] = TileType.FLOOR
			cur.x += 1 if to.x > cur.x else -1
	grid[cur.x][cur.y] = TileType.FLOOR

func _spawn_enemies(floor_num: int) -> void:
	var floor_idx: int = clampi(floor_num - 1, 0, GameState.ENEMIES_PER_FLOOR.size() - 1)
	var enemy_count: int = GameState.ENEMIES_PER_FLOOR[floor_idx]
	var available_types: Array[Enemy.EnemyType] = []

	available_types.append(Enemy.EnemyType.SKELETON_GRUNT)
	if floor_num >= 1:
		available_types.append(Enemy.EnemyType.GOBLIN_ARCHER)
	if floor_num >= 2:
		available_types.append(Enemy.EnemyType.SHIELD_GUARD)
	if floor_num >= 3:
		available_types.append(Enemy.EnemyType.OGRE_BERSERKER)
	if floor_num >= 4:
		available_types.append(Enemy.EnemyType.SHADOW_STALKER)
	if floor_num >= 5:
		available_types.append(Enemy.EnemyType.CULTIST_MAGE)

	var spawn_rooms: Array[Room] = []
	for r in rooms:
		if not r.is_entrance:
			spawn_rooms.append(r)

	for i in range(enemy_count):
		if spawn_rooms.is_empty():
			break
		var room: Room = spawn_rooms[i % spawn_rooms.size()]
		var ex: int = game_state.randi_range(room.rect.position.x + 1, room.rect.position.x + room.rect.size.x - 2)
		var ey: int = game_state.randi_range(room.rect.position.y + 1, room.rect.position.y + room.rect.size.y - 2)
		var epos: Vector2i = Vector2i(ex, ey)

		var occupied: bool = (epos == entrance_pos or epos == exit_pos or grid[epos.x][epos.y] == TileType.CHEST or grid[epos.x][epos.y] == TileType.ALTAR)
		for e in enemies:
			if e.pos == epos:
				occupied = true
				break

		if not occupied:
			var type_idx: int = game_state.randi_range(0, available_types.size() - 1)
			var etype: Enemy.EnemyType = available_types[type_idx]
			var enemy_obj: Enemy = Enemy.new(etype, epos)
			enemies.append(enemy_obj)

func is_walkable(pos: Vector2i) -> bool:
	if pos.x < 0 or pos.x >= width or pos.y < 0 or pos.y >= height:
		return false
	return grid[pos.x][pos.y] != TileType.WALL

