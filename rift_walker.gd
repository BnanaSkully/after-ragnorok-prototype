class_name RiftWalker
extends RefCounted

# A Rift Walker (placeholder name, Nathan 22 Nov): a creature of the roots of
# Yggdrasil that crawls out of a rift during the season (Rifts.SEASON_*).
# The simple version Nathan picked: it wanders near its rift, NEVER attacks
# first, blocks a hex like a unit, and fights back if attacked. Its only effect
# on the land: each Walker standing on a faction's land costs that faction
# Rifts.WALKER_FOOD Food a turn (GameState.food_parts). It is not a Unit: it
# belongs to no faction, so there is no war, peace, zone of control or upkeep.
# The rules for it live in rifts.gd (spawning, wandering) and game_state.gd
# (fighting it); this file is only its data.

# Two kinds (Nathan's lore, 23 Nov): a BROOD is Yggdrasil's rogue army, out of
# a rift in the season; a HORDE is the dead risen as skeletons where a unit
# fell near a rift (Rifts.raise_horde). Same rules; the horde is weaker and
# doesn't heal.
enum Kind { BROOD, HORDE }

const STRENGTH := 3 # a brood: like a fresh army
const MAX_HP := 10 # a brood: like a unit (Unit.MAX_HP)
const HORDE_STRENGTH := 2 # a skeleton horde
const HORDE_MAX_HP := 6

var kind := Kind.BROOD
var strength := STRENGTH
var max_hp := MAX_HP
var pos: Vector2i # the hex it stands on
var home: Vector2i # the rift it came from (it wanders within Rifts.WANDER_RANGE of it)
var hp := MAX_HP
var acted := false # fought this turn (then it doesn't heal)
var on_land := "" # whose land it stood on last turn (to warn only when it wanders onto yours)

func _init(p_pos: Vector2i, p_home: Vector2i, p_kind := Kind.BROOD) -> void:
	pos = p_pos
	home = p_home
	kind = p_kind
	if kind == Kind.HORDE:
		strength = HORDE_STRENGTH
		max_hp = HORDE_MAX_HP
	hp = max_hp

func is_horde() -> bool:
	return kind == Kind.HORDE

# What the game calls it ("a brood", "a skeleton horde").
func label() -> String:
	return "skeleton horde" if is_horde() else "brood"

# Its Strength as wounds weaken it, the same rule as units (never below 1).
func fighting_strength() -> int:
	return maxi(1, roundi(strength * (0.5 + 0.5 * float(hp) / max_hp)))
