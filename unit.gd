class_name Unit
extends RefCounted

# One army unit on the map. Each faction can have several (see Faction.units).
# Only one unit can stand on a hex.

# Who it belongs to. Stored as a "weak" link: the faction keeps its units alive,
# but a unit doesn't keep its faction alive, so Godot can free them both later
# (two objects pointing at each other would otherwise never be cleaned up).
var faction: Faction:
	get:
		return _faction.get_ref()
var _faction: WeakRef

var pos: Vector2i # which hex it stands on
var moves := 1 # moves left this turn
var strength: int # copied from its faction's Strength when built

func _init(p_faction: Faction, p_pos: Vector2i) -> void:
	_faction = weakref(p_faction)
	pos = p_pos
	strength = p_faction.strength
