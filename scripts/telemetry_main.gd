extends SceneTree

# ==============================================================================
# ROGUE-02 / GP-024-R2 — АВТОНОМНАЯ ТОЧКА ВХОДА ТЕЛЕМЕТРИИ
#
# ЗАЧЕМ ЭТОТ ФАЙЛ СУЩЕСТВУЕТ:
# основной способ запуска — флаг --telemetry через диспетчер в main.gd
# (см. PATCH_main_gd_GP024.md). Этот файл — ВТОРОЙ, независимый вход,
# который не требует ни одной правки в main.gd вообще.
#
# Скрипт наследует SceneTree, поэтому Godot запускает его КАК ГЛАВНЫЙ ЦИКЛ
# вместо обычной сцены проекта. main.gd при этом не исполняется вовсе,
# значит существующие режимы физически не могут быть затронуты (AC2):
# в них не меняется ни один символ, они просто не участвуют в запуске.
#
# ЗАПУСК:
#   rm -rf .godot
#   godot --headless --path . --script res://scripts/telemetry_main.gd -- 9001 9100
#   godot --headless --path . --script res://scripts/telemetry_main.gd -- 9001 9100 --csv
#
# Аргументы после "--": первый — начальный сид, второй — конечный.
# Без аргументов берётся диапазон 1..100.
# ==============================================================================

const TelemetryRunner = preload("res://scripts/telemetry_runner.gd")


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()

	var nums: Array[int] = []
	var want_csv: bool = false
	for a in args:
		if a == "--csv":
			want_csv = true
		elif a == "--telemetry":
			continue
		elif a.is_valid_int():
			nums.append(int(a))

	var seed_from: int = 1
	var seed_to: int = 100
	if nums.size() >= 1:
		seed_from = nums[0]
		seed_to = nums[0]
	if nums.size() >= 2:
		seed_to = nums[1]

	# Диапазон, заданный в обратном порядке, нормализуем, а не выполняем
	# вхолостую: "--  9010 9001" должно означать то же, что "-- 9001 9010".
	if seed_to < seed_from:
		var swap: int = seed_from
		seed_from = seed_to
		seed_to = swap

	var runner := TelemetryRunner.new()
	runner.run_range(seed_from, seed_to, want_csv)

	quit(0)


func _process(_delta: float) -> bool:
	# Вся работа выполнена в _initialize; главный цикл не крутится.
	return true

# КОНЕЦ ФАЙЛА scripts/telemetry_main.gd
