class_name Enemy
extends RefCounted

enum EnemyType {
	SKELETON_GRUNT,
	GOBLIN_ARCHER,
	SHIELD_GUARD,
	OGRE_BERSERKER,
	SHADOW_STALKER,
	CULTIST_MAGE
}

enum IntentType {
	NONE,
	MOVE,
	RETREAT,
	ATTACK,
	RANGED_ATTACK,
	SHIELD_UP,
	PREPARE_SLAM,
	SLAM,
	DASH_STRIKE,
	CAST_AOE,
	AOE_DETONATE
}

var type: EnemyType
var name_ru: String
var symbol: String
var color_hex: String
var pos: Vector2i
var hp: int
var max_hp: int
var damage: int

var is_shielded: bool = false
var is_stunned: bool = false
var charge_turns: int = 0
var telegraphed_target: Vector2i = Vector2i.ZERO

var intent_type: IntentType = IntentType.NONE
var intent_target: Vector2i = Vector2i.ZERO
var intent_damage: int = 0
var intent_desc: String = ""

func _init(p_type: EnemyType, p_pos: Vector2i) -> void:
	type = p_type
	pos = p_pos
	match type:
		EnemyType.SKELETON_GRUNT:
			name_ru = "Скелет-пехотинец"
			symbol = "S"
			color_hex = "#E8ECF4"
			max_hp = 8
			hp = 8
			damage = 3
		EnemyType.GOBLIN_ARCHER:
			name_ru = "Гоблин-лучник"
			symbol = "A"
			color_hex = "#8CE870"
			max_hp = 10
			hp = 10
			damage = 4
		EnemyType.SHIELD_GUARD:
			name_ru = "Страж щита"
			symbol = "G"
			color_hex = "#70A8E8"
			max_hp = 16
			hp = 16
			damage = 4
		EnemyType.OGRE_BERSERKER:
			name_ru = "Берсерк-Огр"
			symbol = "O"
			color_hex = "#E85D75"
			max_hp = 20
			hp = 20
			damage = 7
		EnemyType.SHADOW_STALKER:
			name_ru = "Тень-Убийца"
			symbol = "T"
			color_hex = "#B7A8FF"
			max_hp = 12
			hp = 12
			damage = 5
		EnemyType.CULTIST_MAGE:
			name_ru = "Культист-Маг"
			symbol = "M"
			color_hex = "#FF9E4A"
			max_hp = 14
			hp = 14
			damage = 4

func is_alive() -> bool:
	return hp > 0

func take_damage(amount: int) -> int:
	if is_shielded:
		is_shielded = false
		return 0
	var old_hp: int = hp
	hp = maxi(0, hp - amount)
	return old_hp - hp

func set_intent(p_type: IntentType, p_target: Vector2i, p_dmg: int, p_desc: String) -> void:
	intent_type = p_type
	intent_target = p_target
	intent_damage = p_dmg
	intent_desc = p_desc
