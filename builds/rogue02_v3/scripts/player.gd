class_name Player
extends RefCounted

const GameState = preload("res://scripts/game_state.gd")

var pos: Vector2i = Vector2i.ZERO
var hp: int = GameState.PLAYER_MAX_HP
var max_hp: int = GameState.PLAYER_MAX_HP
var focus: int = GameState.PLAYER_START_FOCUS
var max_focus: int = GameState.PLAYER_MAX_FOCUS
var base_damage: int = GameState.PLAYER_BASE_DAMAGE

var is_blocking: bool = false
var game_state: GameState = null

func _init(p_game_state: GameState) -> void:
	game_state = p_game_state
	reset()

func reset() -> void:
	hp = GameState.PLAYER_MAX_HP
	max_hp = GameState.PLAYER_MAX_HP
	focus = GameState.PLAYER_START_FOCUS
	max_focus = GameState.PLAYER_MAX_FOCUS
	base_damage = GameState.PLAYER_BASE_DAMAGE
	is_blocking = false

func add_focus(amount: int = 1) -> void:
	var old_focus: int = focus
	focus = mini(max_focus, focus + amount)
	var gained: int = focus - old_focus
	if gained > 0 and game_state != null:
		game_state.counters["focus_gained"] += gained

func can_afford(cost: int) -> bool:
	return focus >= cost

func spend_focus(cost: int) -> bool:
	if focus >= cost:
		focus -= cost
		return true
	return false

func heal(amount: int) -> int:
	var old_hp: int = hp
	hp = mini(max_hp, hp + amount)
	return hp - old_hp

func take_damage(amount: int, is_pursuit: bool = false) -> int:
	if is_blocking and not is_pursuit:
		is_blocking = false
		return 0
	var old_hp: int = hp
	hp = maxi(0, hp - amount)
	var dealt: int = old_hp - hp
	if game_state != null:
		game_state.counters["damage_taken"] += dealt
		if is_pursuit:
			game_state.counters["pursuit_damage_taken"] += dealt
	if hp <= 0 and game_state != null:
		game_state.game_status = GameState.GameStatus.DEFEAT
		if is_pursuit:
			game_state.finish_reason = "Погиб от скверны преследования (запас исчерпан)."
		else:
			game_state.finish_reason = "Погиб в бою от полученных ран."
	return dealt

func is_alive() -> bool:
	return hp > 0
