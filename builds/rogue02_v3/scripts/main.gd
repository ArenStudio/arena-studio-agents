class_name Main
extends Node2D

const GameState = preload("res://scripts/game_state.gd")
const Player = preload("res://scripts/player.gd")
const DungeonGenerator = preload("res://scripts/dungeon_generator.gd")
const CombatSystem = preload("res://scripts/combat_system.gd")
const Enemy = preload("res://scripts/enemy.gd")

var game_state: GameState
var player: Player
var dungeon: DungeonGenerator
var combat: CombatSystem

var target_mode: String = ""
var cell_size: int = 18
var origin_x: int = 24
var origin_y: int = 90

func _ready() -> void:
	game_state = GameState.new()
	player = Player.new(game_state)
	dungeon = DungeonGenerator.new(game_state)
	combat = CombatSystem.new(game_state, player, dungeon)

	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.is_empty():
		args = OS.get_cmdline_args()

	var is_headless: bool = DisplayServer.get_name() == "headless" or "--headless" in args

	if is_headless:
		_run_headless_mode(args)
	else:
		_start_new_game(12345)

func _start_new_game(seed_val: int) -> void:
	game_state.reset(seed_val)
	player.reset()
	dungeon.generate_floor(1)
	player.pos = dungeon.entrance_pos
	combat.calculate_all_enemy_intents()
	combat.log_message("=== ROGUE-02: ТОЧКА НЕВОЗВРАТА ===")
	combat.log_message("Спуск начат. Запас преследования: 120 единиц на этаж.")
	queue_redraw()

# ==============================================================================
# HEADLESS RUNNER & AUTOMATED AUDIT (AC1 - AC5)
# ==============================================================================
func _run_headless_mode(args: PackedStringArray) -> void:
	var seed_val: int = 12345
	var mode: String = "autoplay"
	var custom_moves: String = ""

	for i in range(args.size()):
		if args[i] == "--seed" and i + 1 < args.size():
			seed_val = args[i + 1].to_int()
		elif args[i] == "--test-wait":
			mode = "test_wait"
		elif args[i] == "--test-determ":
			mode = "test_determ"
		elif args[i] == "--test-victory":
			mode = "test_victory"
		elif args[i] == "--autoplay":
			mode = "autoplay"
		elif args[i] == "--moves" and i + 1 < args.size():
			mode = "moves"
			custom_moves = args[i + 1]

	print("\n[ROGUE-02 HEADLESS INITIALIZED: SEED %d, MODE: %s]" % [seed_val, mode])

	if mode == "test_determ":
		_run_determinism_test(seed_val)
	elif mode == "test_wait":
		_run_wait_doom_test(seed_val)
	elif mode == "test_victory":
		_run_victory_test(seed_val)
	elif mode == "moves":
		_run_custom_moves(seed_val, custom_moves)
	else:
		_run_autoplay_simulation(seed_val)

	get_tree().quit()

func _print_summary(res: Dictionary) -> void:
	print("\n=== ROGUE-02 HEADLESS RUN SUMMARY ===")
	print("SEED: %d" % res["seed"])
	print("FLOOR: %d/%d" % [res["floor"], GameState.MAX_FLOORS])
	print("TOTAL TURNS: %d" % res["turns"])
	print("OUTCOME: %s" % res["outcome"])
	print("REASON: %s" % res["reason"])
	print("PLAYER HP: %d/%d" % [res["hp"], GameState.PLAYER_MAX_HP])
	print("PLAYER FOCUS: %d/%d" % [res["focus"], GameState.PLAYER_MAX_FOCUS])
	print("MECHANIC COUNTERS:")
	print("  - Focus Gained: %d" % res["focus_gained"])
	print("  - Dash Used: %d" % res["dash_used"])
	print("  - Block Used: %d" % res["block_used"])
	print("  - Crush Used: %d" % res["crush_used"])
	print("  - Basic Attacks: %d" % res["basic_attacks"])
	print("  - Moves Made: %d" % res["moves_made"])
	print("  - Waits Made: %d" % res["waits_made"])
	print("  - Enemies Killed: %d" % res["kills"])
	print("  - Total Damage Dealt: %d" % res["dmg_dealt"])
	print("  - Total Damage Taken: %d" % res["dmg_taken"])
	print("  - Pursuit Damage Taken: %d" % res["pursuit_taken"])
	print("  - Floors Cleared: %d" % res["floors_cleared"])
	print("=====================================\n")

func _run_wait_doom_test(seed_val: int) -> void:
	_start_new_game(seed_val)
	dungeon.enemies.clear() # Isolate pure floor pursuit clock
	print("--- ЗАПУСК ТЕСТА БЕЗДЕЙСТВИЯ (ПРЕСЛЕДОВАНИЕ ЭТАЖА) ---")
	while game_state.game_status == GameState.GameStatus.ACTIVE:
		combat.execute_player_wait()

	print("ИТОГ ТЕСТА БЕЗДЕЙСТВИЯ:")
	print("Ходов до гибели: %d (Ожидалось SYS: 28 ходов)" % game_state.total_turns)
	print("Причина завершения: %s" % game_state.finish_reason)
	print("Урон от преследования: %d" % game_state.counters["pursuit_damage_taken"])
	print("SYS ВАЛИДАЦИЯ: %s" % ("PASS (Ровно 28 ходов)" if game_state.total_turns == 28 else "FAIL"))

func _run_determinism_test(seed_val: int) -> void:
	print("--- ЗАПУСК ТЕСТА ДЕТЕРМИНИЗМА (2 ПРОГОНА) ---")
	var result1: Dictionary = _simulate_autoplay(seed_val)
	var result2: Dictionary = _simulate_autoplay(seed_val)

	print("ПРОГОН 1: Floor %d, Turns %d, Outcome: %s, HP: %d, Kills: %d, DmgDealt: %d" % [
		result1["floor"], result1["turns"], result1["outcome"], result1["hp"], result1["kills"], result1["dmg_dealt"]
	])
	print("ПРОГОН 2: Floor %d, Turns %d, Outcome: %s, HP: %d, Kills: %d, DmgDealt: %d" % [
		result2["floor"], result2["turns"], result2["outcome"], result2["hp"], result2["kills"], result2["dmg_dealt"]
	])

	var matched: bool = (result1 == result2)
	print("СТАТУС ДЕТЕРМИНИЗМА: %s" % ("PASS (Побитово идентичны)" if matched else "FAIL"))

func _run_victory_test(seed_val: int) -> void:
	print("--- ЗАПУСК ВАЛИДАЦИИ ПОЛНОГО ЦИКЛА (8 ЭТАЖЕЙ ДО ПОБЕДЫ) ---")
	var res: Dictionary = _simulate_autoplay(seed_val)
	_print_summary(res)
	print("РЕЗУЛЬТАТ ВАЛИДАЦИИ ПОЛНОГО ПРОХОЖДЕНИЯ: %s (Этажей пройдено: %d/8)" % [res["outcome"], res["floors_cleared"]])

func _run_autoplay_simulation(seed_val: int) -> void:
	var res: Dictionary = _simulate_autoplay(seed_val)
	_print_summary(res)

func _simulate_autoplay(seed_val: int) -> Dictionary:
	_start_new_game(seed_val)
	var max_safe_turns: int = 1500

	while game_state.game_status == GameState.GameStatus.ACTIVE and game_state.total_turns < max_safe_turns:
		_ai_decide_and_act()

	return {
		"seed": seed_val,
		"floor": game_state.current_floor,
		"turns": game_state.total_turns,
		"outcome": "VICTORY" if game_state.game_status == GameState.GameStatus.VICTORY else ("DEFEAT" if game_state.game_status == GameState.GameStatus.DEFEAT else "ACTIVE"),
		"reason": game_state.finish_reason,
		"hp": player.hp,
		"focus": player.focus,
		"kills": game_state.counters["enemies_killed"],
		"dmg_dealt": game_state.counters["damage_dealt"],
		"dmg_taken": game_state.counters["damage_taken"],
		"pursuit_taken": game_state.counters["pursuit_damage_taken"],
		"focus_gained": game_state.counters["focus_gained"],
		"dash_used": game_state.counters["dash_used"],
		"block_used": game_state.counters["block_used"],
		"crush_used": game_state.counters["crush_used"],
		"basic_attacks": game_state.counters["basic_attacks"],
		"moves_made": game_state.counters["moves_made"],
		"waits_made": game_state.counters["waits_made"],
		"floors_cleared": game_state.counters["floors_cleared"]
	}

func _run_custom_moves(seed_val: int, moves_str: String) -> void:
	_start_new_game(seed_val)
	var moves: PackedStringArray = moves_str.split(",")

	for m in moves:
		if game_state.game_status != GameState.GameStatus.ACTIVE:
			break
		m = m.strip_edges().to_lower()
		match m:
			"w", "up": combat.execute_player_move(Vector2i(0, -1))
			"s", "down": combat.execute_player_move(Vector2i(0, 1))
			"a", "left": combat.execute_player_move(Vector2i(-1, 0))
			"d", "right": combat.execute_player_move(Vector2i(1, 0))
			"wait", ".": combat.execute_player_wait()
			"stairs", "e": combat.execute_player_use_stairs()
			"block", "2": combat.execute_player_block()
			"dash_w": combat.execute_player_dash(Vector2i(0, -1))
			"dash_s": combat.execute_player_dash(Vector2i(0, 1))
			"dash_a": combat.execute_player_dash(Vector2i(-1, 0))
			"dash_d": combat.execute_player_dash(Vector2i(1, 0))
			"crush_w": combat.execute_player_crush(Vector2i(0, -1))
			"crush_s": combat.execute_player_crush(Vector2i(0, 1))
			"crush_a": combat.execute_player_crush(Vector2i(-1, 0))
			"crush_d": combat.execute_player_crush(Vector2i(1, 0))

	var res: Dictionary = {
		"seed": seed_val,
		"floor": game_state.current_floor,
		"turns": game_state.total_turns,
		"outcome": "VICTORY" if game_state.game_status == GameState.GameStatus.VICTORY else ("DEFEAT" if game_state.game_status == GameState.GameStatus.DEFEAT else "ACTIVE"),
		"reason": game_state.finish_reason,
		"hp": player.hp,
		"focus": player.focus,
		"kills": game_state.counters["enemies_killed"],
		"dmg_dealt": game_state.counters["damage_dealt"],
		"dmg_taken": game_state.counters["damage_taken"],
		"pursuit_taken": game_state.counters["pursuit_damage_taken"],
		"focus_gained": game_state.counters["focus_gained"],
		"dash_used": game_state.counters["dash_used"],
		"block_used": game_state.counters["block_used"],
		"crush_used": game_state.counters["crush_used"],
		"basic_attacks": game_state.counters["basic_attacks"],
		"moves_made": game_state.counters["moves_made"],
		"waits_made": game_state.counters["waits_made"],
		"floors_cleared": game_state.counters["floors_cleared"]
	}
	_print_summary(res)

func _ai_decide_and_act() -> void:
	# 1. Take Stairs if standing on Exit
	if player.pos == dungeon.exit_pos:
		combat.execute_player_use_stairs()
		return

	var dirs: Array[Vector2i] = [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]
	var adjacent_enemies: Array[Enemy] = []
	for d in dirs:
		var e: Enemy = combat.get_enemy_at(player.pos + d)
		if e != null and e.is_alive():
			adjacent_enemies.append(e)

	# 2. Evade Telegraphed Danger (Ogre Slam or Mage AoE)
	for e in dungeon.enemies:
		if e.is_alive() and e.charge_turns > 0:
			var in_danger: bool = false
			if e.intent_type == Enemy.IntentType.SLAM and player.pos == e.intent_target:
				in_danger = true
			elif e.intent_type == Enemy.IntentType.AOE_DETONATE:
				if absi(player.pos.x - e.intent_target.x) <= 1 and absi(player.pos.y - e.intent_target.y) <= 1:
					in_danger = true

			if in_danger:
				for d in dirs:
					var safe_cand: Vector2i = player.pos + d
					if dungeon.is_walkable(safe_cand) and combat.get_enemy_at(safe_cand) == null:
						var cand_in_aoe: bool = (e.intent_type == Enemy.IntentType.AOE_DETONATE and absi(safe_cand.x - e.intent_target.x) <= 1 and absi(safe_cand.y - e.intent_target.y) <= 1)
						var cand_in_slam: bool = (e.intent_type == Enemy.IntentType.SLAM and safe_cand == e.intent_target)
						if not cand_in_aoe and not cand_in_slam:
							combat.execute_player_move(d)
							return

	# 3. COMBAT RESOLUTION (Balanced distribution across Attack, Crush, Block, Dash)
	if not adjacent_enemies.is_empty():
		# A. Kill 1-hit killable enemy immediately (basic attack)
		for e in adjacent_enemies:
			if not e.is_shielded and e.hp <= player.base_damage:
				combat.execute_player_basic_attack(e)
				return

		# B. Crush high-HP dangerous enemy (Ogre, Guard, Cultist, Stalker)
		if player.can_afford(GameState.COST_CRUSH):
			for e in adjacent_enemies:
				if e.hp >= 5 and not e.is_shielded:
					combat.execute_player_crush(e.pos - player.pos)
					return

		# C. Block incoming heavy attacks (damage >= 4) when healthy or critical
		var heavy_threat: bool = false
		for e in adjacent_enemies:
			if e.intent_type == Enemy.IntentType.ATTACK and e.intent_damage >= 4 and not e.is_stunned:
				heavy_threat = true
				break
		if heavy_threat and player.can_afford(GameState.COST_BLOCK) and player.hp <= 16:
			combat.execute_player_block()
			return

		# D. Dash out if surrounded by 2+ enemies
		if adjacent_enemies.size() >= 2 and player.can_afford(GameState.COST_DASH):
			for d in dirs:
				var step2: Vector2i = player.pos + d * 2
				if dungeon.is_walkable(step2) and combat.get_enemy_at(step2) == null:
					combat.execute_player_dash(d)
					return

		# E. Attack unshielded enemy
		var unshielded: Array[Enemy] = []
		for e in adjacent_enemies:
			if not e.is_shielded:
				unshielded.append(e)
		if not unshielded.is_empty():
			unshielded.sort_custom(func(a, b): return a.hp < b.hp)
			combat.execute_player_basic_attack(unshielded[0])
			return

		# F. Block if enemy is shielded
		if player.can_afford(GameState.COST_BLOCK):
			combat.execute_player_block()
			return
		combat.execute_player_basic_attack(adjacent_enemies[0])
		return

	# 4. DASH USAGE (Gap-close on Archer/Mage at distance 2)
	if player.can_afford(GameState.COST_DASH):
		for d in dirs:
			var target2: Vector2i = player.pos + d * 2
			var e2: Enemy = combat.get_enemy_at(target2)
			if e2 != null and e2.is_alive() and dungeon.is_walkable(player.pos + d):
				combat.execute_player_dash(d)
				return

	# 5. Collect nearby Altars of Focus or Chests (within distance 7)
	var target_pickup: Vector2i = Vector2i(-1, -1)
	var min_pickup_dist: int = 8

	for a_pos in dungeon.altars:
		if dungeon.grid[a_pos.x][a_pos.y] == DungeonGenerator.TileType.ALTAR:
			var d: int = absi(player.pos.x - a_pos.x) + absi(player.pos.y - a_pos.y)
			if d < min_pickup_dist:
				min_pickup_dist = d
				target_pickup = a_pos

	for c_pos in dungeon.chests:
		if dungeon.grid[c_pos.x][c_pos.y] == DungeonGenerator.TileType.CHEST:
			var d: int = absi(player.pos.x - c_pos.x) + absi(player.pos.y - c_pos.y)
			if d < min_pickup_dist:
				min_pickup_dist = d
				target_pickup = c_pos

	if target_pickup != Vector2i(-1, -1):
		var step_item: Vector2i = _get_best_nav_step(player.pos, target_pickup)
		if step_item != player.pos:
			combat.execute_player_move(step_item - player.pos)
			return

	# 6. If healthy (> 12 HP), engage nearby enemies within distance 3
	if player.hp > 12:
		var nearest_enemy: Enemy = null
		var nearest_dist: int = 999
		for e in dungeon.enemies:
			if e.is_alive():
				var d: int = absi(player.pos.x - e.pos.x) + absi(player.pos.y - e.pos.y)
				if d < nearest_dist and d <= 3:
					nearest_dist = d
					nearest_enemy = e

		if nearest_enemy != null:
			var step_to_enemy: Vector2i = _get_best_nav_step(player.pos, nearest_enemy.pos)
			if step_to_enemy != player.pos:
				combat.execute_player_move(step_to_enemy - player.pos)
				return

	# 7. Navigate directly to Exit stairs
	var next_step: Vector2i = _get_best_nav_step(player.pos, dungeon.exit_pos)
	if next_step != player.pos:
		var move_dir: Vector2i = next_step - player.pos
		combat.execute_player_move(move_dir)
	else:
		combat.execute_player_wait()

func _get_best_nav_step(from: Vector2i, to: Vector2i) -> Vector2i:
	if from == to:
		return from

	var queue: Array[Vector2i] = [from]
	var came_from: Dictionary = {}
	came_from[from] = from
	var dirs: Array[Vector2i] = [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]
	var found: bool = false

	while not queue.is_empty():
		var current: Vector2i = queue.pop_front()
		if current == to:
			found = true
			break

		for d in dirs:
			var next: Vector2i = current + d
			if dungeon.is_walkable(next) and not came_from.has(next):
				came_from[next] = current
				queue.append(next)

	if not found:
		var best_cand: Vector2i = from
		var best_dist: float = 1e9
		for cell in came_from.keys():
			var d: float = Vector2(cell).distance_to(Vector2(to))
			if d < best_dist and cell != from:
				best_dist = d
				best_cand = cell
		if best_cand != from:
			to = best_cand
		else:
			return from

	var curr: Vector2i = to
	while came_from.has(curr) and came_from[curr] != from:
		curr = came_from[curr]

	return curr

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.is_pressed() or event.is_echo():
		return

	if game_state.game_status != GameState.GameStatus.ACTIVE:
		if event.keycode == KEY_R or event.keycode == KEY_ENTER:
			_start_new_game(game_state.current_seed + 1)
		return

	var key: Key = event.keycode
	var move_dir: Vector2i = Vector2i.ZERO

	if key == KEY_W or key == KEY_UP: move_dir = Vector2i(0, -1)
	elif key == KEY_S or key == KEY_DOWN: move_dir = Vector2i(0, 1)
	elif key == KEY_A or key == KEY_LEFT: move_dir = Vector2i(-1, 0)
	elif key == KEY_D or key == KEY_RIGHT: move_dir = Vector2i(1, 0)

	if target_mode == "DASH":
		if move_dir != Vector2i.ZERO:
			target_mode = ""
			combat.execute_player_dash(move_dir)
			queue_redraw()
		elif key == KEY_ESCAPE:
			target_mode = ""
			combat.log_message("Рывок отменён.")
			queue_redraw()
		return

	if target_mode == "CRUSH":
		if move_dir != Vector2i.ZERO:
			target_mode = ""
			combat.execute_player_crush(move_dir)
			queue_redraw()
		elif key == KEY_ESCAPE:
			target_mode = ""
			combat.log_message("Сокрушение отменено.")
			queue_redraw()
		return

	if move_dir != Vector2i.ZERO:
		combat.execute_player_move(move_dir)
		queue_redraw()
		return

	if key == KEY_1:
		if player.can_afford(GameState.COST_DASH):
			target_mode = "DASH"
			combat.log_message("РЫВОК: выберите направление стрелками/WASD (Esc - отмена)...")
		else:
			combat.log_message("Недостаточно Фокуса для Рывка (нужно 2)!")
		queue_redraw()
		return

	if key == KEY_2:
		combat.execute_player_block()
		queue_redraw()
		return

	if key == KEY_3:
		if player.can_afford(GameState.COST_CRUSH):
			target_mode = "CRUSH"
			combat.log_message("СОКРУШЕНИЕ: укажите направление на врага стрелками/WASD...")
		else:
			combat.log_message("Недостаточно Фокуса для Сокрушения (нужно 2)!")
		queue_redraw()
		return

	if key == KEY_SPACE or key == KEY_PERIOD:
		combat.execute_player_wait()
		queue_redraw()
		return

	if key == KEY_E or key == KEY_ENTER:
		combat.execute_player_use_stairs()
		queue_redraw()
		return

	if key == KEY_R:
		_start_new_game(game_state.current_seed)
		queue_redraw()
		return

func _draw() -> void:
	draw_rect(Rect2(0, 0, 1280, 720), Color("#10131C"))

	if dungeon == null or dungeon.grid.is_empty():
		return

	for x in range(dungeon.width):
		for y in range(dungeon.height):
			var tile: DungeonGenerator.TileType = dungeon.grid[x][y]
			var rect: Rect2 = Rect2(origin_x + x * cell_size, origin_y + y * cell_size, cell_size - 1, cell_size - 1)
			match tile:
				DungeonGenerator.TileType.WALL:
					draw_rect(rect, Color("#2B3044"))
				DungeonGenerator.TileType.FLOOR:
					draw_rect(rect, Color("#181D2B"))
				DungeonGenerator.TileType.ENTRANCE:
					draw_rect(rect, Color("#18303B"))
					draw_string(ThemeDB.fallback_font, rect.position + Vector2(4, 13), "<", HORIZONTAL_ALIGNMENT_CENTER, -1, 12, Color("#66E6FF"))
				DungeonGenerator.TileType.EXIT:
					draw_rect(rect, Color("#38321B"))
					draw_string(ThemeDB.fallback_font, rect.position + Vector2(4, 13), ">", HORIZONTAL_ALIGNMENT_CENTER, -1, 12, Color("#FFD978"))
				DungeonGenerator.TileType.CHEST:
					draw_rect(rect, Color("#38251B"))
					draw_string(ThemeDB.fallback_font, rect.position + Vector2(4, 13), "$", HORIZONTAL_ALIGNMENT_CENTER, -1, 12, Color("#FFD978"))
				DungeonGenerator.TileType.ALTAR:
					draw_rect(rect, Color("#251C38"))
					draw_string(ThemeDB.fallback_font, rect.position + Vector2(4, 13), "&", HORIZONTAL_ALIGNMENT_CENTER, -1, 12, Color("#B7A8FF"))

	for e in dungeon.enemies:
		if e.is_alive() and e.charge_turns > 0:
			if e.intent_type == Enemy.IntentType.SLAM:
				var tpos: Vector2i = e.intent_target
				var r: Rect2 = Rect2(origin_x + tpos.x * cell_size, origin_y + tpos.y * cell_size, cell_size - 1, cell_size - 1)
				draw_rect(r, Color(1.0, 0.2, 0.2, 0.45))
			elif e.intent_type == Enemy.IntentType.AOE_DETONATE:
				var center: Vector2i = e.intent_target
				for ax in range(center.x - 1, center.x + 2):
					for ay in range(center.y - 1, center.y + 2):
						if ax >= 0 and ax < dungeon.width and ay >= 0 and ay < dungeon.height:
							var r: Rect2 = Rect2(origin_x + ax * cell_size, origin_y + ay * cell_size, cell_size - 1, cell_size - 1)
							draw_rect(r, Color(1.0, 0.4, 0.1, 0.35))

	for e in dungeon.enemies:
		if e.is_alive():
			var rect: Rect2 = Rect2(origin_x + e.pos.x * cell_size, origin_y + e.pos.y * cell_size, cell_size - 1, cell_size - 1)
			draw_rect(rect, Color(e.color_hex))
			draw_string(ThemeDB.fallback_font, rect.position + Vector2(4, 13), e.symbol, HORIZONTAL_ALIGNMENT_CENTER, -1, 12, Color("#10131C"))

			var hp_ratio: float = float(e.hp) / float(e.max_hp)
			draw_rect(Rect2(rect.position.x, rect.position.y - 3, cell_size - 1, 2), Color("#333333"))
			draw_rect(Rect2(rect.position.x, rect.position.y - 3, (cell_size - 1) * hp_ratio, 2), Color("#FF6B7A"))

	var p_rect: Rect2 = Rect2(origin_x + player.pos.x * cell_size, origin_y + player.pos.y * cell_size, cell_size - 1, cell_size - 1)
	draw_rect(p_rect, Color("#66E6FF"))
	draw_string(ThemeDB.fallback_font, p_rect.position + Vector2(3, 13), "@", HORIZONTAL_ALIGNMENT_CENTER, -1, 13, Color("#10131C"))

	draw_rect(Rect2(0, 0, 1280, 72), Color("#161A26"))
	draw_line(Vector2(0, 72), Vector2(1280, 72), Color("#65708A"), 1.0)

	draw_string(ThemeDB.fallback_font, Vector2(24, 30), "ЭТАЖ: %d / %d" % [game_state.current_floor, GameState.MAX_FLOORS], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("#E8ECF4"))
	draw_string(ThemeDB.fallback_font, Vector2(24, 54), "ХОД: %d   (СИД: %d)" % [game_state.total_turns, game_state.current_seed], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#8993A7"))

	var hp_color: Color = Color("#66E6FF") if player.hp > 8 else Color("#FF6B7A")
	draw_string(ThemeDB.fallback_font, Vector2(260, 30), "ЗДОРОВЬЕ: %d / %d" % [player.hp, player.max_hp], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, hp_color)
	draw_rect(Rect2(260, 38, 180, 10), Color("#222838"))
	draw_rect(Rect2(260, 38, 180 * (float(player.hp) / float(player.max_hp)), 10), hp_color)

	var focus_text: String = ""
	for f in range(player.max_focus):
		focus_text += "◆ " if f < player.focus else "◇ "
	draw_string(ThemeDB.fallback_font, Vector2(470, 30), "ФОКУС: %s(%d/%d)" % [focus_text, player.focus, player.max_focus], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("#FFD978"))
	draw_string(ThemeDB.fallback_font, Vector2(470, 52), "+1 за убийство, +3 алтарь/тайник", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#8993A7"))

	var pursuit_color: Color = Color("#77D9F0")
	if game_state.pursuit_remaining <= 30:
		pursuit_color = Color("#FF6B7A")
	elif game_state.pursuit_remaining <= 60:
		pursuit_color = Color("#FFD978")

	draw_string(ThemeDB.fallback_font, Vector2(740, 30), "ПРЕСЛЕДОВАНИЕ: %d / 120" % maxi(0, game_state.pursuit_remaining), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, pursuit_color)
	draw_rect(Rect2(740, 38, 180, 10), Color("#222838"))
	draw_rect(Rect2(740, 38, 180 * (clampf(float(game_state.pursuit_remaining) / 120.0, 0.0, 1.0)), 10), pursuit_color)
	draw_string(ThemeDB.fallback_font, Vector2(740, 58), "Ход -1, Пропуск -6. Скверна при 0!", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("#8993A7"))

	draw_string(ThemeDB.fallback_font, Vector2(960, 24), "[1] Рывок (2Ф)   [2] Блок (1Ф)", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#66E6FF"))
	draw_string(ThemeDB.fallback_font, Vector2(960, 42), "[3] Сокрушение (2Ф) [Space] Ждать", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#66E6FF"))
	draw_string(ThemeDB.fallback_font, Vector2(960, 60), "[WASD] Перемещение/Удар [E] Лестница", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#E8ECF4"))

	var sb_x: int = 860
	draw_rect(Rect2(sb_x, origin_y, 400, 600), Color("#141722"))
	draw_line(Vector2(sb_x, origin_y), Vector2(sb_x, origin_y + 600), Color("#404B69"), 1.0)

	draw_string(ThemeDB.fallback_font, Vector2(sb_x + 16, origin_y + 24), "НАМЕРЕНИЯ ВРАГОВ НА СЛЕДУЮЩИЙ ХОД:", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#FFD978"))

	var line_y: int = origin_y + 50
	var living_count: int = 0
	for e in dungeon.enemies:
		if e.is_alive():
			living_count += 1
			var info: String = "[%s] %s: %s (HP %d/%d)" % [e.symbol, e.name_ru, e.intent_desc, e.hp, e.max_hp]
			draw_string(ThemeDB.fallback_font, Vector2(sb_x + 16, line_y), info, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(e.color_hex))
			line_y += 24
			if line_y > origin_y + 280:
				break

	if living_count == 0:
		draw_string(ThemeDB.fallback_font, Vector2(sb_x + 16, line_y), "Все враги на этаже зачищены!", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#8CE870"))

	var log_y: int = origin_y + 320
	draw_line(Vector2(sb_x + 10, log_y - 15), Vector2(sb_x + 390, log_y - 15), Color("#404B69"), 1.0)
	draw_string(ThemeDB.fallback_font, Vector2(sb_x + 16, log_y), "ЖУРНАЛ СОБЫТИЙ:", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#E8ECF4"))

	var entry_y: int = log_y + 24
	var logs_to_show: Array[String] = combat.combat_log.slice(-10)
	for msg in logs_to_show:
		draw_string(ThemeDB.fallback_font, Vector2(sb_x + 16, entry_y), msg, HORIZONTAL_ALIGNMENT_LEFT, 370, 11, Color("#CCD2E0"))
		entry_y += 22

	if game_state.game_status != GameState.GameStatus.ACTIVE:
		draw_rect(Rect2(200, 200, 880, 320), Color(0.06, 0.08, 0.12, 0.92))
		draw_rect(Rect2(200, 200, 880, 320), Color("#65708A"), false, 2.0)

		var title_col: Color = Color("#FFD978") if game_state.game_status == GameState.GameStatus.VICTORY else Color("#FF6B7A")
		var title_txt: String = "ПОБЕДА! СПУСК ЗАВЕРШЁН" if game_state.game_status == GameState.GameStatus.VICTORY else "ПОРАЖЕНИЕ: СМЕРТЬ В ПОДЗЕМЕЛЬЕ"
		draw_string(ThemeDB.fallback_font, Vector2(240, 260), title_txt, HORIZONTAL_ALIGNMENT_CENTER, 800, 24, title_col)
		draw_string(ThemeDB.fallback_font, Vector2(240, 300), game_state.finish_reason, HORIZONTAL_ALIGNMENT_CENTER, 800, 15, Color("#E8ECF4"))

		var stat_str: String = "Ходов: %d   Убито врагов: %d   Нанесено урона: %d   Получено урона: %d" % [
			game_state.total_turns, game_state.counters["enemies_killed"], game_state.counters["damage_dealt"], game_state.counters["damage_taken"]
		]
		draw_string(ThemeDB.fallback_font, Vector2(240, 350), stat_str, HORIZONTAL_ALIGNMENT_CENTER, 800, 13, Color("#8993A7"))

		var skills_str: String = "Применения: Рывок %d | Блок %d | Сокрушение %d | Набрано фокуса: %d" % [
			game_state.counters["dash_used"], game_state.counters["block_used"], game_state.counters["crush_used"], game_state.counters["focus_gained"]
		]
		draw_string(ThemeDB.fallback_font, Vector2(240, 380), skills_str, HORIZONTAL_ALIGNMENT_CENTER, 800, 13, Color("#8993A7"))

		draw_string(ThemeDB.fallback_font, Vector2(240, 450), "Нажмите [ENTER] или [R] для нового спуска", HORIZONTAL_ALIGNMENT_CENTER, 800, 16, Color("#66E6FF"))

