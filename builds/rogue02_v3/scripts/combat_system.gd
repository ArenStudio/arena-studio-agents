class_name CombatSystem
extends RefCounted

const GameState = preload("res://scripts/game_state.gd")
const Player = preload("res://scripts/player.gd")
const DungeonGenerator = preload("res://scripts/dungeon_generator.gd")
const Enemy = preload("res://scripts/enemy.gd")

var game_state: GameState
var player: Player
var dungeon: DungeonGenerator
var combat_log: Array[String] = []

func _init(p_game_state: GameState, p_player: Player, p_dungeon: DungeonGenerator) -> void:
	game_state = p_game_state
	player = p_player
	dungeon = p_dungeon

func log_message(msg: String) -> void:
	combat_log.append(msg)
	if combat_log.size() > 30:
		combat_log.pop_front()

func get_enemy_at(target_pos: Vector2i) -> Enemy:
	for e in dungeon.enemies:
		if e.is_alive() and e.pos == target_pos:
			return e
	return null

func calculate_all_enemy_intents() -> void:
	for e in dungeon.enemies:
		if not e.is_alive():
			continue
		if e.is_stunned:
			e.set_intent(Enemy.IntentType.NONE, e.pos, 0, "Оглушён (пропуск хода)")
			continue

		var dist: int = _manhattan(e.pos, player.pos)
		var is_adjacent: bool = (dist == 1)

		match e.type:
			Enemy.EnemyType.SKELETON_GRUNT:
				if is_adjacent:
					e.set_intent(Enemy.IntentType.ATTACK, player.pos, e.damage, "Удар костями (%d)" % e.damage)
				else:
					var step: Vector2i = _get_step_towards(e.pos, player.pos)
					e.set_intent(Enemy.IntentType.MOVE, step, 0, "Движение к игроку")

			Enemy.EnemyType.GOBLIN_ARCHER:
				if is_adjacent:
					var retreat_tile: Vector2i = _get_retreat_step(e.pos, player.pos)
					e.set_intent(Enemy.IntentType.RETREAT, retreat_tile, 0, "Отступление на дистанцию")
				elif dist >= 2 and dist <= 4 and _has_los(e.pos, player.pos):
					e.set_intent(Enemy.IntentType.RANGED_ATTACK, player.pos, e.damage, "Прицельный выстрел (%d)" % e.damage)
				else:
					var step: Vector2i = _get_step_towards(e.pos, player.pos)
					e.set_intent(Enemy.IntentType.MOVE, step, 0, "Движение на позицию стрельбы")

			Enemy.EnemyType.SHIELD_GUARD:
				if is_adjacent:
					if e.is_shielded:
						e.set_intent(Enemy.IntentType.ATTACK, player.pos, e.damage, "Удар булавой (%d)" % e.damage)
					else:
						e.set_intent(Enemy.IntentType.SHIELD_UP, e.pos, 0, "Глухая защита (Блок 100%)")
				else:
					var step: Vector2i = _get_step_towards(e.pos, player.pos)
					e.set_intent(Enemy.IntentType.MOVE, step, 0, "Движение со щитом")

			Enemy.EnemyType.OGRE_BERSERKER:
				if e.charge_turns > 0:
					e.set_intent(Enemy.IntentType.SLAM, e.telegraphed_target, e.damage, "СОКРУШИТЕЛЬНЫЙ УДАР (%d)" % e.damage)
				elif is_adjacent:
					e.set_intent(Enemy.IntentType.PREPARE_SLAM, player.pos, 0, "Замах дубиной (Удар в %s на сл. ход)" % str(player.pos))
				else:
					var step: Vector2i = _get_step_towards(e.pos, player.pos)
					e.set_intent(Enemy.IntentType.MOVE, step, 0, "Тяжёлые шаги к игроку")

			Enemy.EnemyType.SHADOW_STALKER:
				if is_adjacent:
					e.set_intent(Enemy.IntentType.ATTACK, player.pos, e.damage, "Кинжалы из тени (%d)" % e.damage)
				elif dist == 2 and (e.pos.x == player.pos.x or e.pos.y == player.pos.y):
					var mid: Vector2i = Vector2i((e.pos.x + player.pos.x) / 2, (e.pos.y + player.pos.y) / 2)
					if dungeon.is_walkable(mid) and get_enemy_at(mid) == null:
						e.set_intent(Enemy.IntentType.DASH_STRIKE, player.pos, e.damage, "Теневой выпад (%d)" % e.damage)
					else:
						var step: Vector2i = _get_step_towards(e.pos, player.pos)
						e.set_intent(Enemy.IntentType.MOVE, step, 0, "Обход с фланга")
				else:
					var step: Vector2i = _get_step_towards(e.pos, player.pos)
					e.set_intent(Enemy.IntentType.MOVE, step, 0, "Крадущееся сближение")

			Enemy.EnemyType.CULTIST_MAGE:
				if e.charge_turns > 0:
					e.set_intent(Enemy.IntentType.AOE_DETONATE, e.telegraphed_target, e.damage, "Взрыв скверны (%d в зоне 3x3)" % e.damage)
				elif dist <= 5:
					e.set_intent(Enemy.IntentType.CAST_AOE, player.pos, 0, "Ритуал скверны (Зона 3x3 вокруг %s)" % str(player.pos))
				else:
					var step: Vector2i = _get_step_towards(e.pos, player.pos)
					e.set_intent(Enemy.IntentType.MOVE, step, 0, "Приближение для ритуала")

func execute_player_move(dir: Vector2i) -> bool:
	var target: Vector2i = player.pos + dir
	var enemy_on_target: Enemy = get_enemy_at(target)
	if enemy_on_target != null:
		return execute_player_basic_attack(enemy_on_target)

	if not dungeon.is_walkable(target):
		log_message("Путь заблокирован стеной.")
		return false

	player.pos = target
	game_state.counters["moves_made"] += 1

	if dungeon.grid[target.x][target.y] == DungeonGenerator.TileType.CHEST:
		dungeon.grid[target.x][target.y] = DungeonGenerator.TileType.FLOOR
		var healed: int = player.heal(10)
		player.add_focus(3)
		log_message("Открыт тайник! Восстановлено +%d HP и +3 Фокуса." % healed)
	elif dungeon.grid[target.x][target.y] == DungeonGenerator.TileType.ALTAR:
		dungeon.grid[target.x][target.y] = DungeonGenerator.TileType.FLOOR
		var healed: int = player.heal(4)
		player.add_focus(3)
		log_message("Алтарь Концентрации активирован! +3 Фокуса, +%d HP." % healed)

	_finish_player_turn(GameState.PURSUIT_COST_ACTION)
	return true

func execute_player_basic_attack(enemy: Enemy) -> bool:
	var dealt: int = enemy.take_damage(player.base_damage)
	game_state.counters["basic_attacks"] += 1
	game_state.counters["damage_dealt"] += dealt
	if dealt == 0 and enemy.is_shielded:
		log_message("%s заблокировал ваш удар щитом!" % enemy.name_ru)
	else:
		log_message("Вы нанесли %s %d урона. (HP: %d/%d)" % [enemy.name_ru, dealt, enemy.hp, enemy.max_hp])

	_finish_player_turn(GameState.PURSUIT_COST_ACTION)
	return true

func execute_player_dash(dir: Vector2i) -> bool:
	if not player.can_afford(GameState.COST_DASH):
		log_message("Недостаточно Фокуса для Рывка (нужно %d)." % GameState.COST_DASH)
		return false

	var step1: Vector2i = player.pos + dir
	var step2: Vector2i = player.pos + dir * 2
	var final_pos: Vector2i = player.pos

	if dungeon.is_walkable(step2) and get_enemy_at(step2) == null:
		final_pos = step2
	elif dungeon.is_walkable(step1) and get_enemy_at(step1) == null:
		final_pos = step1
	else:
		log_message("Нет свободного места для Рывка в этом направлении!")
		return false

	player.spend_focus(GameState.COST_DASH)
	game_state.counters["dash_used"] += 1
	player.pos = final_pos
	log_message("Вы совершили стремительный Рывок!")

	if dungeon.grid[final_pos.x][final_pos.y] == DungeonGenerator.TileType.CHEST:
		dungeon.grid[final_pos.x][final_pos.y] = DungeonGenerator.TileType.FLOOR
		var healed: int = player.heal(10)
		player.add_focus(3)
		log_message("Рывком взят тайник! +%d HP и +3 Фокуса." % healed)
	elif dungeon.grid[final_pos.x][final_pos.y] == DungeonGenerator.TileType.ALTAR:
		dungeon.grid[final_pos.x][final_pos.y] = DungeonGenerator.TileType.FLOOR
		var healed: int = player.heal(4)
		player.add_focus(3)
		log_message("Рывком активирован Алтарь Концентрации! +3 Фокуса, +%d HP." % healed)

	var passed_enemy: Enemy = get_enemy_at(step1)
	if passed_enemy != null and passed_enemy.is_alive():
		var dealt: int = passed_enemy.take_damage(2)
		game_state.counters["damage_dealt"] += dealt
		log_message("Рывок рассёк %s на %d урона!" % [passed_enemy.name_ru, dealt])

	_finish_player_turn(GameState.PURSUIT_COST_ACTION)
	return true

func execute_player_block() -> bool:
	if not player.can_afford(GameState.COST_BLOCK):
		log_message("Недостаточно Фокуса для Блока (нужно %d)." % GameState.COST_BLOCK)
		return false

	player.spend_focus(GameState.COST_BLOCK)
	player.is_blocking = true
	game_state.counters["block_used"] += 1
	log_message("Вы подняли глухую защиту (Блок 100% урона на 1 ход)!")

	_finish_player_turn(GameState.PURSUIT_COST_ACTION)
	return true

func execute_player_crush(target_dir: Vector2i) -> bool:
	if not player.can_afford(GameState.COST_CRUSH):
		log_message("Недостаточно Фокуса для Сокрушения (нужно %d)." % GameState.COST_CRUSH)
		return false

	var target_pos: Vector2i = player.pos + target_dir
	var enemy: Enemy = get_enemy_at(target_pos)
	if enemy == null:
		log_message("В этой клетке нет врага для Сокрушения!")
		return false

	player.spend_focus(GameState.COST_CRUSH)
	game_state.counters["crush_used"] += 1

	var crush_dmg: int = player.base_damage * 2
	var dealt: int = enemy.take_damage(crush_dmg)
	enemy.is_stunned = true
	game_state.counters["damage_dealt"] += dealt
	log_message("СОКРУШЕНИЕ! %s получил %d урона и оглушён на 1 ход!" % [enemy.name_ru, dealt])

	_finish_player_turn(GameState.PURSUIT_COST_ACTION)
	return true

func execute_player_wait() -> bool:
	game_state.counters["waits_made"] += 1
	log_message("Вы выжидаете... (Преследование -%d)" % GameState.PURSUIT_COST_WAIT)
	_finish_player_turn(GameState.PURSUIT_COST_WAIT)
	return true

func execute_player_use_stairs() -> bool:
	if player.pos != dungeon.exit_pos:
		log_message("Здесь нет спуска на следующий этаж!")
		return false

	var rest_heal: int = player.heal(6)
	log_message("Вы спустились на этаж %d! Передышка восстановила +%d HP." % [game_state.current_floor + 1, rest_heal])
	game_state.next_floor()
	if game_state.game_status == GameState.GameStatus.VICTORY:
		log_message(game_state.finish_reason)
		return true

	dungeon.generate_floor(game_state.current_floor)
	player.pos = dungeon.entrance_pos
	calculate_all_enemy_intents()
	return true

func _finish_player_turn(pursuit_cost: int) -> void:
	game_state.total_turns += 1

	_check_enemy_deaths()
	_resolve_enemy_actions()
	_update_pursuit(pursuit_cost)

	player.is_blocking = false

	if game_state.game_status == GameState.GameStatus.ACTIVE:
		calculate_all_enemy_intents()

func _check_enemy_deaths() -> void:
	for e in dungeon.enemies:
		if not e.is_alive() and e.hp <= 0 and e.max_hp > 0:
			e.max_hp = 0
			game_state.counters["enemies_killed"] += 1
			player.add_focus(1)
			log_message("%s повержен! (+1 Фокус, всего: %d/%d)" % [e.name_ru, player.focus, player.max_focus])

func _resolve_enemy_actions() -> void:
	for e in dungeon.enemies:
		if not e.is_alive():
			continue

		if e.intent_type != Enemy.IntentType.SHIELD_UP:
			e.is_shielded = false

		if e.is_stunned:
			e.is_stunned = false
			log_message("%s восстановился после оглушения." % e.name_ru)
			continue

		match e.intent_type:
			Enemy.IntentType.MOVE, Enemy.IntentType.RETREAT:
				if dungeon.is_walkable(e.intent_target) and get_enemy_at(e.intent_target) == null and e.intent_target != player.pos:
					e.pos = e.intent_target

			Enemy.IntentType.ATTACK:
				if _manhattan(e.pos, player.pos) == 1:
					if player.is_blocking:
						log_message("Вы парировали удар %s щитом!" % e.name_ru)
					else:
						var taken: int = player.take_damage(e.intent_damage)
						log_message("%s атаковал вас на %d урона! (HP: %d/%d)" % [e.name_ru, taken, player.hp, player.max_hp])

			Enemy.IntentType.RANGED_ATTACK:
				var dist: int = _manhattan(e.pos, player.pos)
				if dist >= 2 and dist <= 4 and _has_los(e.pos, player.pos):
					if player.is_blocking:
						log_message("Вы закрылись щитом от выстрела %s!" % e.name_ru)
					else:
						var taken: int = player.take_damage(e.intent_damage)
						log_message("%s выстрелил в вас на %d урона! (HP: %d/%d)" % [e.name_ru, taken, player.hp, player.max_hp])

			Enemy.IntentType.SHIELD_UP:
				e.is_shielded = true
				log_message("%s поднял щит в глухую защиту!" % e.name_ru)

			Enemy.IntentType.PREPARE_SLAM:
				e.charge_turns = 1
				e.telegraphed_target = player.pos
				log_message("%s заносит тяжёлую дубину над клеткой %s!" % [e.name_ru, str(e.telegraphed_target)])

			Enemy.IntentType.SLAM:
				e.charge_turns = 0
				if player.pos == e.intent_target:
					if player.is_blocking:
						log_message("Вы приняли сокрушительный удар %s на щит!" % e.name_ru)
					else:
						var taken: int = player.take_damage(e.intent_damage)
						log_message("%s ОБРУШИЛ ДУБИНУ на %d урона!" % [e.name_ru, taken])
				else:
					log_message("%s сокрушил пустое место! Вы вовремя отошли." % e.name_ru)

			Enemy.IntentType.DASH_STRIKE:
				var mid: Vector2i = Vector2i((e.pos.x + player.pos.x) / 2, (e.pos.y + player.pos.y) / 2)
				if dungeon.is_walkable(mid) and get_enemy_at(mid) == null:
					e.pos = mid
				if player.is_blocking:
					log_message("Теневой выпад %s парирован щитом!" % e.name_ru)
				else:
					var taken: int = player.take_damage(e.intent_damage)
					log_message("%s совершил теневой рывок и ранил вас на %d урона!" % [e.name_ru, taken])

			Enemy.IntentType.CAST_AOE:
				e.charge_turns = 1
				e.telegraphed_target = player.pos
				log_message("%s начертил ритуальный круг скверны вокруг %s!" % [e.name_ru, str(e.telegraphed_target)])

			Enemy.IntentType.AOE_DETONATE:
				e.charge_turns = 0
				var center: Vector2i = e.intent_target
				if absi(player.pos.x - center.x) <= 1 and absi(player.pos.y - center.y) <= 1:
					var taken: int = player.take_damage(e.intent_damage)
					log_message("РИТУАЛ СКВЕРНЫ сдетонировал! Вы получили %d урона!" % taken)
				else:
					log_message("Ритуал скверны взорвался в стороне (%s)!" % str(center))

func _update_pursuit(cost: int) -> void:
	game_state.pursuit_remaining -= cost
	if game_state.pursuit_remaining < 0:
		var taken: int = player.take_damage(GameState.PURSUIT_DAMAGE_PER_TURN, true)
		log_message("ПРЕСЛЕДОВАНИЕ ЭТАЖА: Скверна наносит %d урона! Запас исчерпан!" % taken)

func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)

func _get_step_towards(from: Vector2i, to: Vector2i) -> Vector2i:
	var dirs: Array[Vector2i] = [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]
	var best_step: Vector2i = from
	var best_dist: int = _manhattan(from, to)

	for d in dirs:
		var cand: Vector2i = from + d
		if dungeon.is_walkable(cand) and get_enemy_at(cand) == null and cand != player.pos:
			var cur_dist: int = _manhattan(cand, to)
			if cur_dist < best_dist:
				best_dist = cur_dist
				best_step = cand
	return best_step

func _get_retreat_step(from: Vector2i, away_from: Vector2i) -> Vector2i:
	var dirs: Array[Vector2i] = [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]
	var best_step: Vector2i = from
	var max_dist: int = _manhattan(from, away_from)

	for d in dirs:
		var cand: Vector2i = from + d
		if dungeon.is_walkable(cand) and get_enemy_at(cand) == null and cand != player.pos:
			var cur_dist: int = _manhattan(cand, away_from)
			if cur_dist > max_dist:
				max_dist = cur_dist
				best_step = cand
	return best_step

func _has_los(from: Vector2i, to: Vector2i) -> bool:
	var x0: int = from.x
	var y0: int = from.y
	var x1: int = to.x
	var y1: int = to.y

	var dx: int = absi(x1 - x0)
	var dy: int = absi(y1 - y0)
	var sx: int = 1 if x0 < x1 else -1
	var sy: int = 1 if y0 < y1 else -1
	var err: int = dx - dy

	var cx: int = x0
	var cy: int = y0

	while true:
		if cx == x1 and cy == y1:
			return true
		if (cx != x0 or cy != y0) and (cx != x1 or cy != y1):
			if not dungeon.is_walkable(Vector2i(cx, cy)):
				return false
		var e2: int = 2 * err
		if e2 > -dy:
			err -= dy
			cx += sx
		if e2 < dx:
			err += dx
			cy += sy
	return true

