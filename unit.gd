class_name Unit
extends RefCounted

# One unit on the map. Each faction can have several (see Faction.units).
# Only one unit can stand on a hex. There are two kinds:
#   ARMY  - the normal fighting unit (1 move, the faction's Strength, eats Food)
#   SCOUT - fast and weak: 2 moves, Strength 1, sees further, eats nothing
#           (the usual 4X explorer)

enum Kind { ARMY, SCOUT }

const ARMY_SIGHT := 2 # fog of war: hexes an army unit sees around itself
const SCOUT_MOVES := 2
const SCOUT_STRENGTH := 1
const SCOUT_SIGHT := 3
# Health (standard 4X): fights damage both sides; a unit at 0 HP dies. A unit
# that neither moves nor fights in a turn heals (GameState.HEAL_*). A wounded
# unit fights weaker: half its Strength at 0 HP, rising to full at MAX_HP.
const MAX_HP := 10

# Who it belongs to. Stored as a "weak" link: the faction keeps its units alive,
# but a unit doesn't keep its faction alive, so Godot can free them both later
# (two objects pointing at each other would otherwise never be cleaned up).
var faction: Faction:
	get:
		return _faction.get_ref()
var _faction: WeakRef

var kind := Kind.ARMY
var pos: Vector2i # which hex it stands on
var moves := 1 # moves left this turn
var strength: int # an army copies its faction's Strength when built
var busy_until := 0 # standing watch (an event): it can't move before this turn
var hp := MAX_HP
var acted := false # moved or fought this turn (then it doesn't heal)

func _init(p_faction: Faction, p_pos: Vector2i, p_kind := Kind.ARMY) -> void:
	_faction = weakref(p_faction)
	pos = p_pos
	kind = p_kind
	strength = SCOUT_STRENGTH if kind == Kind.SCOUT else p_faction.strength
	moves = max_moves()

# Its Strength as wounds weaken it (never below 1).
func fighting_strength() -> int:
	return maxi(1, roundi(strength * (0.5 + 0.5 * float(hp) / MAX_HP)))

func is_scout() -> bool:
	return kind == Kind.SCOUT

func max_moves() -> int:
	return SCOUT_MOVES if is_scout() else 1

func sight() -> int:
	return SCOUT_SIGHT if is_scout() else ARMY_SIGHT

# Food it eats each turn (scouts live off the land).
func upkeep(per_army: int) -> int:
	return 0 if is_scout() else per_army
