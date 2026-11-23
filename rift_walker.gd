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

const STRENGTH := 3 # like a fresh army
const MAX_HP := 10 # like a unit (Unit.MAX_HP)

var pos: Vector2i # the hex it stands on
var home: Vector2i # the rift it came out of (it wanders within Rifts.WANDER_RANGE of it)
var hp := MAX_HP
var acted := false # fought this turn (then it doesn't heal)
var on_land := "" # whose land it stood on last turn (to warn only when it wanders onto yours)

func _init(p_pos: Vector2i, p_home: Vector2i) -> void:
	pos = p_pos
	home = p_home

# Its Strength as wounds weaken it, the same rule as units (never below 1).
func fighting_strength() -> int:
	return maxi(1, roundi(STRENGTH * (0.5 + 0.5 * float(hp) / MAX_HP)))
