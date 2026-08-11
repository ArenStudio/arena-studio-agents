class_name GameState
extends RefCounted

# ==============================================================================
# SYS PARAMETERS & CONSTANTS (PROJECT: ROGUE-02)
# ==============================================================================
const MAX_FLOORS: int = 8
const PLAYER_MAX_HP: int = 24
const PLAYER_BASE_DAMAGE: int = 4
const PLAYER_START_FOCUS: int = 3
const PLAYER_MAX_FOCUS: int = 5

const PURSUIT_MAX_PER_FLOOR: int = 120
const PURSUIT_COST_ACTION: int = 1
const PURSUIT_COST_WAIT: int = 6
const PURSUIT_DAMAGE_PER_TURN: int = 3 # 120/6=20 safe wait turns + 24/3=8 turns = exactly 28 turns to perish

# Skill focus costs
const COST_DASH: int = 2
const COST_BLOCK: int = 1
const COST_CRUSH: int = 2

# Game outcome enums
enum GameStatus {
	ACTIVE,
	VICTORY,
	DEFEAT
}

# ==============================================================================
# STATE VARIABLES
# ==============================================================================
var current_seed: int = 12345
var current_floor: int = 1
var total_turns: int = 0
var game_status: GameStatus = GameStatus.ACTIVE
var finish_reason: String = ""

# Floor pursuit
var pursuit_remaining: int = PURSUIT_MAX_PER_FLOOR

# Mechanic counters (AC7)
var counters = {
	"focus_gained": 0,
	"dash_used": 0,
	"block_used": 0,
	"crush_used": 0,
	"basic_attacks": 0,
	"moves_made": 0,
	"waits_made": 0,
	"enemies_killed": 0,
	"damage_dealt": 0,
	"damage_taken": 0,
	"pursuit_damage_taken": 0,
	"floors_cleared": 0
}

# Deterministic RNG state (Mulberry32)
var _rng_state: int = 0

func set_seed(seed_val: int) -> void:
	current_seed = seed_val
	_rng_state = seed_val & 0xFFFFFFFF

func rand_u32() -> int:
	_rng_state = (_rng_state + 0x6D2B79F5) & 0xFFFFFFFF
	var t: int = _rng_state ^ (_rng_state >> 15)
	t = (t * (1 | _rng_state)) & 0xFFFFFFFF
	t = (t + (t ^ (t >> 7)) * (61 | t)) & 0xFFFFFFFF
	return (t ^ (t >> 14)) & 0xFFFFFFFF

func randf() -> float:
	return float(rand_u32()) / 4294967296.0

func randi_range(from: int, to: int) -> int:
	if from >= to:
		return from
	var span: int = to - from + 1
	return from + (rand_u32() % span)

func reset(seed_val: int = 12345) -> void:
	set_seed(seed_val)
	current_floor = 1
	total_turns = 0
	game_status = GameStatus.ACTIVE
	finish_reason = ""
	pursuit_remaining = PURSUIT_MAX_PER_FLOOR
	for k in counters.keys():
		counters[k] = 0

func next_floor() -> void:
	counters["floors_cleared"] += 1
	current_floor += 1
	pursuit_remaining = PURSUIT_MAX_PER_FLOOR
	if current_floor > MAX_FLOORS:
		game_status = GameStatus.VICTORY
		finish_reason = "Спуск успешно завершён! Пройдено 8 этажей подземелья."
