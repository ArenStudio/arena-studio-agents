class_name RunTelemetry
extends RefCounted

# ==============================================================================
# ROGUE-02 / GP-024 — ТЕЛЕМЕТРИЯ ПРОГОНА
#
# КОНТРАКТ: модуль ТОЛЬКО ЧИТАЕТ состояние. Он не двигает игрока, не трогает
# врагов, не наносит урон, не берёт числа из ГПСЧ (rand_u32/randf/randi_range)
# и не вызывает game_state.hash_u32(). Поэтому включение телеметрии не может
# изменить ход игры: хеш прогона с телеметрией и без обязан совпасть (AC2).
#
# Из чужого кода вызываются только чистые функции чтения:
#   combat._has_los(a, b)      — Брезенхэм по dungeon.is_walkable, состояние не меняет
#   combat.get_enemy_at(cell)  — поиск по dungeon.enemies, состояние не меняет
#   dungeon.is_walkable(cell)
# Всё остальное — локальная арифметика.
#
# ПОРЯДОК ВЫЗОВОВ (на один прогон):
#   begin_run(seed)
#   ... для каждого хода, ПОСЛЕ расчёта намерений врагов и ДО действия игрока:
#   sample_turn(game_state, player, dungeon, combat)
#   ... после завершения прогона:
#   end_run(game_state, player)
#   ... после всего диапазона сидов:
#   print(format_summary())
# ==============================================================================

const Enemy = preload("res://scripts/enemy.gd")
const GameState = preload("res://scripts/game_state.gd")

const BUCKET_LABELS: Array[String] = ["0", "1-3", "4-6", "7-9", "10+"]

# Сколько последних ходов перед гибелью анализируется (метрика 4).
const DEATH_WINDOW: int = 5

# ------------------------------------------------------------------ агрегаты
var runs: int = 0
var runs_victory: int = 0
var runs_defeat: int = 0
var turns_total: int = 0

# Метрика 1: безопасные клетки.
var safe_hist: Array[int] = [0, 0, 0, 0, 0, 0]
var turns_zero_safe: int = 0
var turns_zero_safe_even_with_dash: int = 0
var turns_zero_safe_dash_strike: int = 0

# Метрика 2: размер пакета входящего урона.
var packet_buckets: Array[int] = [0, 0, 0, 0, 0]
var damage_total: int = 0
var pursuit_damage_total: int = 0

# Метрика 3: окружение.
var turns_encircled: int = 0
var turns_threatened_2plus: int = 0
var adjacent_hist: Array[int] = [0, 0, 0, 0, 0]

# Метрика 4: предрешённость гибели.
var turns_no_surviving_action: int = 0
var deaths_predetermined: int = 0
var deaths_bot_error: int = 0
var deaths_last_moment: int = 0
var deaths_by_pursuit: int = 0
var floor_of_death: Dictionary = {}

# Метрика 5: Фокус.
var turns_focus_dry: int = 0
var turns_focus_dry_pressed: int = 0
var focus_hist: Array[int] = [0, 0, 0, 0, 0, 0]

# Метрика 6 (добавлена GP по предписанию GD «входы в комнаты»).
var degree_hist: Array[int] = [0, 0, 0, 0, 0]
var turns_corridor_pressed: int = 0

# Построчный CSV по прогонам (включается флагом verbose).
var verbose: bool = false
var csv_lines: Array[String] = []

# --------------------------------------------------------- состояние прогона
var _seed: int = 0
var _prev_damage: int = 0
var _prev_pursuit: int = 0
var _last_pursuit_delta: int = 0
var _pending: bool = false
var _survive_ring: Array[int] = []
var _last_had_surviving: bool = true
var _run_turns: int = 0
var _run_zero_safe: int = 0
var _run_encircled: int = 0
var _run_damage: int = 0


func begin_run(seed_val: int) -> void:
	_seed = seed_val
	_prev_damage = 0
	_prev_pursuit = 0
	_last_pursuit_delta = 0
	_pending = false
	_survive_ring.clear()
	_last_had_surviving = true
	_run_turns = 0
	_run_zero_safe = 0
	_run_encircled = 0
	_run_damage = 0


# Замер одного хода. Вызывается ДО действия игрока, когда намерения врагов
# на этот ход уже объявлены — то есть ровно та картина, которую видит игрок.
func sample_turn(game_state, player, dungeon, combat) -> void:
	_settle_damage(game_state)
	_pending = true
	_run_turns += 1
	turns_total += 1

	var cells: Array = _available_cells(player, dungeon, combat)

	# --- метрика 1: безопасные клетки ---
	var safe: int = 0
	for c in cells:
		if _threats_on(c, dungeon, combat).is_empty():
			safe += 1
	var idx_safe: int = safe
	if idx_safe > 5:
		idx_safe = 5
	safe_hist[idx_safe] += 1

	var has_dash_strike: bool = false
	for e in dungeon.enemies:
		if e.is_alive() and not e.is_stunned and e.intent_type == Enemy.IntentType.DASH_STRIKE:
			has_dash_strike = true

	if safe == 0:
		turns_zero_safe += 1
		_run_zero_safe += 1
		if has_dash_strike:
			turns_zero_safe_dash_strike += 1
		var dash_safe: bool = false
		if player.focus >= GameState.COST_DASH:
			for c in _dash_cells(player, dungeon, combat):
				if _threats_on(c, dungeon, combat).is_empty():
					dash_safe = true
		if not dash_safe:
			turns_zero_safe_even_with_dash += 1

	# --- метрика 3: окружение ---
	var adjacent: int = 0
	for e in dungeon.enemies:
		if e.is_alive() and _man(e.pos, player.pos) == 1:
			adjacent += 1
	var idx_adj: int = adjacent
	if idx_adj > 4:
		idx_adj = 4
	adjacent_hist[idx_adj] += 1
	if adjacent >= 2:
		turns_encircled += 1
		_run_encircled += 1
	if _threats_on(player.pos, dungeon, combat).size() >= 2:
		turns_threatened_2plus += 1

	# --- метрика 5: Фокус ---
	var idx_focus: int = player.focus
	if idx_focus < 0:
		idx_focus = 0
	if idx_focus > 5:
		idx_focus = 5
	focus_hist[idx_focus] += 1
	if player.focus < GameState.COST_BLOCK:
		turns_focus_dry += 1
		if adjacent >= 1:
			turns_focus_dry_pressed += 1

	# --- метрика 6: геометрия клетки ---
	var degree: int = 0
	for d in _dirs():
		if dungeon.is_walkable(player.pos + d):
			degree += 1
	degree_hist[degree] += 1
	if degree <= 2 and adjacent >= 1:
		turns_corridor_pressed += 1

	# --- метрика 4: существует ли спасающее действие ---
	var survivable: bool = _has_surviving_action(game_state, player, dungeon, combat)
	_last_had_surviving = survivable
	if not survivable:
		turns_no_surviving_action += 1
	_survive_ring.append(1 if survivable else 0)
	if _survive_ring.size() > DEATH_WINDOW:
		_survive_ring.pop_front()


func end_run(game_state, player) -> void:
	_settle_damage(game_state)
	runs += 1

	var outcome: String = "ACTIVE"
	if game_state.game_status == GameState.GameStatus.VICTORY:
		runs_victory += 1
		outcome = "VICTORY"
	elif game_state.game_status == GameState.GameStatus.DEFEAT:
		runs_defeat += 1
		outcome = "DEFEAT"
		var f: int = game_state.current_floor
		floor_of_death[f] = int(floor_of_death.get(f, 0)) + 1

		var forced: bool = _survive_ring.size() > 0
		for v in _survive_ring:
			if v == 1:
				forced = false
		if forced:
			deaths_predetermined += 1
		elif _last_had_surviving:
			deaths_bot_error += 1
		else:
			deaths_last_moment += 1
		if _last_pursuit_delta > 0:
			deaths_by_pursuit += 1

	if verbose:
		csv_lines.append("%d,%s,%d,%d,%d,%d,%d,%d" % [
			_seed, outcome, game_state.current_floor, _run_turns,
			_run_zero_safe, _run_encircled, _run_damage, player.hp
		])


# ============================================================ чтение картины

func _dirs() -> Array:
	return [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]


func _man(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


# Клетки, доступные игроку в этом ходу: текущая (остаться, ударить, Блок)
# плюс соседние проходимые и свободные. Шаг в клетку врага в v22/v23 —
# это атака, а не перемещение, поэтому такая клетка недоступна.
func _available_cells(player, dungeon, combat) -> Array:
	var out: Array = [player.pos]
	for d in _dirs():
		var cand: Vector2i = player.pos + d
		if dungeon.is_walkable(cand) and combat.get_enemy_at(cand) == null:
			out.append(cand)
	return out


# Клетки, достижимые Рывком. Повторяет выбор из execute_player_dash:
# сначала пробуется шаг на 2, при неудаче — на 1.
func _dash_cells(player, dungeon, combat) -> Array:
	var out: Array = []
	for d in _dirs():
		var step1: Vector2i = player.pos + d
		var step2: Vector2i = player.pos + d * 2
		if dungeon.is_walkable(step2) and combat.get_enemy_at(step2) == null:
			out.append(step2)
		elif dungeon.is_walkable(step1) and combat.get_enemy_at(step1) == null:
			out.append(step1)
	return out


# Все объявленные пакеты урона, которые прилетели бы в клетку cell.
# Условия дословно повторяют ветки _resolve_enemy_actions в combat_system.gd.
func _threats_on(cell: Vector2i, dungeon, combat) -> Array:
	var out: Array = []
	var i: int = -1
	for e in dungeon.enemies:
		i += 1
		if not e.is_alive():
			continue
		if e.is_stunned:
			continue
		var d: int = 0
		var is_aoe: bool = false
		match e.intent_type:
			Enemy.IntentType.ATTACK:
				if _man(e.pos, cell) == 1:
					d = e.intent_damage
			Enemy.IntentType.RANGED_ATTACK:
				var dist: int = _man(e.pos, cell)
				if dist >= 2 and dist <= 4 and combat._has_los(e.pos, cell):
					d = e.intent_damage
			Enemy.IntentType.SLAM:
				if cell == e.intent_target:
					d = e.intent_damage
			Enemy.IntentType.DASH_STRIKE:
				# В v22/v23 эта ветка бьёт без повторной проверки дистанции:
				# уклониться перемещением нельзя, угроза накрывает любую клетку.
				d = e.intent_damage
			Enemy.IntentType.AOE_DETONATE:
				var c: Vector2i = e.intent_target
				if absi(cell.x - c.x) <= 1 and absi(cell.y - c.y) <= 1:
					d = e.intent_damage
					is_aoe = true
			_:
				d = 0
		if d > 0:
			out.append({"i": i, "d": d, "aoe": is_aoe})
	return out


func _max_threat(threats: Array, skip_index: int = -1) -> int:
	var m: int = 0
	for t in threats:
		if int(t["i"]) == skip_index:
			continue
		if int(t["d"]) > m:
			m = int(t["d"])
	return m


func _max_aoe_threat(threats: Array) -> int:
	var m: int = 0
	for t in threats:
		if not bool(t["aoe"]):
			continue
		if int(t["d"]) > m:
			m = int(t["d"])
	return m


func _pursuit_damage(game_state, cost: int) -> int:
	if game_state.pursuit_remaining - cost < 0:
		return GameState.PURSUIT_DAMAGE_PER_TURN
	return 0


# Существует ли действие, после которого игрок гарантированно остаётся жив.
# Оценка урона — ВЕРХНЯЯ: берётся максимальный пакет, который может прилететь
# в клетку. В v23 за ход прилетает ровно один пакет, поэтому максимум является
# точной верхней границей, а не суммой (сумма была бы оценкой v22).
func _has_surviving_action(game_state, player, dungeon, combat) -> bool:
	var hp: int = player.hp
	var pur: int = _pursuit_damage(game_state, GameState.PURSUIT_COST_ACTION)

	# 1. Остаться на месте / шагнуть в соседнюю клетку.
	for c in _available_cells(player, dungeon, combat):
		if hp - (_max_threat(_threats_on(c, dungeon, combat)) + pur) > 0:
			return true

	var here: Array = _threats_on(player.pos, dungeon, combat)

	# 2. Блок. Гасит обычную атаку, выстрел, Сокрушительный удар и теневой
	#    выпад, но НЕ гасит взрыв скверны: в ветке AOE_DETONATE проверки
	#    player.is_blocking нет.
	if player.focus >= GameState.COST_BLOCK:
		if hp - (_max_aoe_threat(here) + pur) > 0:
			return true

	# 3. Сокрушение соседа: цель получает оглушение и в этом ходу не действует.
	if player.focus >= GameState.COST_CRUSH:
		var i: int = -1
		for e in dungeon.enemies:
			i += 1
			if not e.is_alive():
				continue
			if _man(e.pos, player.pos) != 1:
				continue
			if hp - (_max_threat(here, i) + pur) > 0:
				return true

	# 4. Рывок.
	if player.focus >= GameState.COST_DASH:
		for c in _dash_cells(player, dungeon, combat):
			if hp - (_max_threat(_threats_on(c, dungeon, combat)) + pur) > 0:
				return true

	return false


# Разносит фактически полученный урон по корзинам. Считается по счётчикам
# game_state, а не по формуле телеметрии (DL-024).
func _settle_damage(game_state) -> void:
	if not _pending:
		_prev_damage = int(game_state.counters["damage_taken"])
		_prev_pursuit = int(game_state.counters["pursuit_damage_taken"])
		return
	var now_damage: int = int(game_state.counters["damage_taken"])
	var now_pursuit: int = int(game_state.counters["pursuit_damage_taken"])
	var delta: int = now_damage - _prev_damage
	var delta_pursuit: int = now_pursuit - _prev_pursuit
	_prev_damage = now_damage
	_prev_pursuit = now_pursuit
	_last_pursuit_delta = delta_pursuit
	_pending = false

	if delta < 0:
		delta = 0
	damage_total += delta
	pursuit_damage_total += delta_pursuit
	_run_damage += delta
	packet_buckets[_bucket_of(delta)] += 1


func _bucket_of(dmg: int) -> int:
	if dmg <= 0:
		return 0
	if dmg <= 3:
		return 1
	if dmg <= 6:
		return 2
	if dmg <= 9:
		return 3
	return 4


# ==================================================================== отчёт

func _pct(part: int, whole: int) -> String:
	if whole <= 0:
		return "  n/a"
	return "%5.1f%%" % (100.0 * float(part) / float(whole))


func format_summary() -> String:
	var s: String = ""
	s += "\n================ ТЕЛЕМЕТРИЯ GP-024 ================\n"
	s += "прогонов: %d   побед: %d   поражений: %d   ходов всего: %d\n" % [
		runs, runs_victory, runs_defeat, turns_total
	]

	s += "\n-- 1. БЕЗОПАСНЫЕ КЛЕТКИ (из текущей + доступных соседних) --\n"
	for i in range(safe_hist.size()):
		s += "   безопасных %d : %7d  %s\n" % [i, safe_hist[i], _pct(safe_hist[i], turns_total)]
	s += "   ХОДОВ С НУЛЁМ БЕЗОПАСНЫХ КЛЕТОК: %d  %s\n" % [turns_zero_safe, _pct(turns_zero_safe, turns_total)]
	s += "   из них не спасает и Рывок       : %d  %s\n" % [
		turns_zero_safe_even_with_dash, _pct(turns_zero_safe_even_with_dash, turns_total)
	]
	s += "   из них при теневом выпаде       : %d  %s\n" % [
		turns_zero_safe_dash_strike, _pct(turns_zero_safe_dash_strike, turns_total)
	]

	s += "\n-- 2. РАЗМЕР ПАКЕТА ВХОДЯЩЕГО УРОНА ЗА ХОД --\n"
	for i in range(packet_buckets.size()):
		s += "   урон %-4s : %7d  %s\n" % [BUCKET_LABELS[i], packet_buckets[i], _pct(packet_buckets[i], turns_total)]
	s += "   суммарный урон: %d, из них Преследование: %d\n" % [damage_total, pursuit_damage_total]

	s += "\n-- 3. ОКРУЖЕНИЕ --\n"
	for i in range(adjacent_hist.size()):
		s += "   врагов вплотную %d : %7d  %s\n" % [i, adjacent_hist[i], _pct(adjacent_hist[i], turns_total)]
	s += "   ДВА И БОЛЕЕ ВПЛОТНУЮ            : %d  %s\n" % [turns_encircled, _pct(turns_encircled, turns_total)]
	s += "   два и более объявили урон по вам: %d  %s\n" % [turns_threatened_2plus, _pct(turns_threatened_2plus, turns_total)]

	s += "\n-- 4. ПРЕДРЕШЁННОСТЬ ГИБЕЛИ --\n"
	s += "   ходов без спасающего действия   : %d  %s\n" % [turns_no_surviving_action, _pct(turns_no_surviving_action, turns_total)]
	s += "   смертей предрешённых (все %d хода окна без выхода): %d  %s\n" % [
		DEATH_WINDOW, deaths_predetermined, _pct(deaths_predetermined, runs_defeat)
	]
	s += "   смертей при живом выходе (ошибка бота)           : %d  %s\n" % [
		deaths_bot_error, _pct(deaths_bot_error, runs_defeat)
	]
	s += "   смертей на последнем ходу без выхода             : %d  %s\n" % [
		deaths_last_moment, _pct(deaths_last_moment, runs_defeat)
	]
	s += "   добито Преследованием                            : %d  %s\n" % [
		deaths_by_pursuit, _pct(deaths_by_pursuit, runs_defeat)
	]
	var floors: Array = floor_of_death.keys()
	floors.sort()
	for f in floors:
		s += "   этаж гибели %d : %d\n" % [f, int(floor_of_death[f])]

	s += "\n-- 5. ФОКУС --\n"
	for i in range(focus_hist.size()):
		s += "   Фокус %d : %7d  %s\n" % [i, focus_hist[i], _pct(focus_hist[i], turns_total)]
	s += "   НЕ ХВАТАЕТ НИ НА ОДИН НАВЫК (Фокус 0): %d  %s\n" % [turns_focus_dry, _pct(turns_focus_dry, turns_total)]
	s += "   то же и враг вплотную                : %d  %s\n" % [
		turns_focus_dry_pressed, _pct(turns_focus_dry_pressed, turns_total)
	]

	s += "\n-- 6. ГЕОМЕТРИЯ КЛЕТКИ (по предписанию GD: входы в комнаты) --\n"
	for i in range(degree_hist.size()):
		s += "   проходимых соседей %d : %7d  %s\n" % [i, degree_hist[i], _pct(degree_hist[i], turns_total)]
	s += "   тупик/коридор (<=2) под давлением: %d  %s\n" % [
		turns_corridor_pressed, _pct(turns_corridor_pressed, turns_total)
	]
	s += "===================================================\n"
	return s


func format_csv() -> String:
	var s: String = "seed,outcome,floor,turns,zero_safe_turns,encircled_turns,damage_taken,hp_left\n"
	for line in csv_lines:
		s += line + "\n"
	return s

# КОНЕЦ ФАЙЛА scripts/telemetry.gd
