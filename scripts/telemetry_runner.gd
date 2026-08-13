class_name TelemetryRunner
extends RefCounted

# ==============================================================================
# ROGUE-02 / GP-024 — РЕЖИМ --telemetry A B
#
# Прогоняет сиды от A до B включительно и печатает сводку RunTelemetry.
#
# ПОЧЕМУ ОТДЕЛЬНЫЙ ФАЙЛ, А НЕ ПРАВКА ЦИКЛА В main.gd:
# существующие режимы (--eval-batch, --autoplay, --manual, --test-determ,
# --test-wait) не должны измениться ни на символ (AC1). Весь новый код лежит
# в новых файлах; в main.gd требуется ровно одна вставка-диспетчер, которая
# ничего не выполняет, пока в аргументах нет "--telemetry".
#
# СТЫКОВКА С ПРОЕКТОМ (сигнатуры подтверждены PROD в GP-024-R3):
#   GameState.new()                                   game_state.gd
#   Player.new(game_state)                            player.gd:19
#   DungeonGenerator.new(game_state)                  dungeon_generator.gd:55
#   CombatSystem.new(game_state, player, dungeon)     combat_system.gd:19
#   Autoplayer.new(game_state, player, dungeon, combat)  autoplayer.gd:19
#   bot.decide_and_act()                              autoplayer.gd:25
# Порядок создания повторяет main.gd:23-27.
# ==============================================================================

const GameState = preload("res://scripts/game_state.gd")
const Player = preload("res://scripts/player.gd")
const DungeonGenerator = preload("res://scripts/dungeon_generator.gd")
const CombatSystem = preload("res://scripts/combat_system.gd")
const Autoplayer = preload("res://scripts/autoplayer.gd")
const RunTelemetry = preload("res://scripts/telemetry.gd")

# Предохранитель от зависшего прогона. Совпадает по смыслу с лимитом
# существующего --eval-batch; на исход влияет только в патологии.
const MAX_TURNS_PER_RUN: int = 4000


# Разбор аргументов. Возвращает true, если режим отработал.
# НЕ static и НЕ ссылается на собственное имя класса: при запуске через
# --script глобальные class_name ещё не зарегистрированы, и самоссылка
# TelemetryRunner.new() падает с "Identifier not found".
func handle_args(args: PackedStringArray) -> bool:
	var idx: int = -1
	for i in range(args.size()):
		if args[i] == "--telemetry":
			idx = i
	if idx < 0:
		return false

	var a: int = 1
	var b: int = 100
	if idx + 1 < args.size():
		a = int(args[idx + 1])
	if idx + 2 < args.size():
		b = int(args[idx + 2])
	if b < a:
		var t: int = a
		a = b
		b = t

	var want_csv: bool = false
	for s in args:
		if s == "--csv":
			want_csv = true

	run_range(a, b, want_csv)
	return true


func run_range(seed_from: int, seed_to: int, want_csv: bool = false) -> void:
	var tel := RunTelemetry.new()
	tel.verbose = want_csv

	print("GP-024 телеметрия: сиды %d..%d (%d прогонов)" % [seed_from, seed_to, seed_to - seed_from + 1])

	for s in range(seed_from, seed_to + 1):
		_one_run(s, tel)

	print(tel.format_summary())
	if want_csv:
		print(tel.format_csv())


# Один прогон. Копия обычного цикла автоигры плюс ОДИН вызов tel.sample_turn().
func _one_run(seed_val: int, tel) -> void:
	# --- СТЫКОВКА 1: порядок и сигнатуры по эталону main.gd:23-27 ---
	var game_state := GameState.new()
	game_state.reset(seed_val)

	var player := Player.new(game_state)
	var dungeon := DungeonGenerator.new(game_state)
	var combat := CombatSystem.new(game_state, player, dungeon)
	var bot := Autoplayer.new(game_state, player, dungeon, combat)

	dungeon.generate_floor(game_state.current_floor)
	player.pos = dungeon.entrance_pos
	combat.calculate_all_enemy_intents()
	# --- конец СТЫКОВКИ 1 ---

	tel.begin_run(seed_val)

	var guard: int = 0
	while game_state.game_status == GameState.GameStatus.ACTIVE and guard < MAX_TURNS_PER_RUN:
		guard += 1

		# Замер ДО действия игрока: намерения врагов на этот ход уже объявлены,
		# то есть измеряется ровно та картина, которую видит игрок.
		# Функция только читает состояние (см. шапку telemetry.gd).
		tel.sample_turn(game_state, player, dungeon, combat)

		# --- СТЫКОВКА 2: один ход бота ---
		# Имя подтверждено PROD в GP-024-R2: decide_and_act().
		bot.decide_and_act()
		# --- конец СТЫКОВКИ 2 ---

	tel.end_run(game_state, player)

# КОНЕЦ ФАЙЛА scripts/telemetry_runner.gd
