class_name Rifts
extends RefCounted

# Rifts in the void: openings into the roots of Yggdrasil, torn open when the
# ark landed. Sköll comes through them (skoll.gd). Every standing city gets
# one rift 4-7 hexes away and at least 4 from every other city (place). The
# rift BELONGS to that city: he comes out of a random rift and hunts the city
# it belongs to, so every city is about equally likely (fair by design; rifts
# by map section hit the player 2:1, and "nearest city" left crowded AI
# cities without a rift). They're rolled on RIFT_TURN (after the Landing, so
# they can keep away from every city) and stay HIDDEN until found (a faction
# that sees one remembers it in Faction.known_rifts) or used. Each time he's
# driven back they're rolled again.
#
# Only rules live here (no drawing): main.gd and view_3d.gd read cells and
# revealed to show them.

const RIFT_TURN := 2 # the turn the rifts are first rolled
const MIN_CITY_DISTANCE := 4 # rifts stay at least this far from every city (was 3: he came out one step from a city's walls)
const MAX_CITY_DISTANCE := 7 # ...and at most this far from the city they belong to

# The GameState (game_state.gd). A "weak" link: the game keeps this object alive,
# but this object doesn't keep the game alive, so Godot can free both later.
var game: GameState:
	get:
		return _game.get_ref()
var _game: WeakRef
var cells: Array[Vector2i] = [] # the current rifts (hidden until found)
var city := {} # rift hex -> name of the faction whose city that rift opened toward
var revealed := HexMap.NO_CELL # the rift Sköll last came through (shown to whoever sees it)

func _init(p_game: GameState) -> void:
	_game = weakref(p_game)

func has(cell: Vector2i) -> bool:
	return cell in cells

# Forget every rift (a new game's Crossing).
func clear() -> void:
	cells.clear()
	city.clear()
	revealed = HexMap.NO_CELL

# One rift per standing city: a random hex MIN_CITY_DISTANCE to
# MAX_CITY_DISTANCE from that city and at least MIN_CITY_DISTANCE from every
# other city. Rolling them again closes the old ones: nobody knows the new ones.
func place() -> void:
	if not game.player.known_rifts.is_empty():
		game.add_message("The ground shudders: the rifts you found have closed, and new ones have torn open somewhere in the dark.")
	game.forget_rifts()
	cells.clear()
	city.clear()
	for f in game.factions:
		if not f.is_alive():
			continue
		var options: Array[Vector2i] = []
		for reach in range(MAX_CITY_DISTANCE, 99): # widen only if a crowded map leaves no room
			for row in HexMap.ROWS:
				for col in HexMap.COLS:
					var c := Vector2i(col, row)
					if spot_ok(c, f, reach):
						options.append(c)
			if not options.is_empty() or reach > HexMap.COLS + HexMap.ROWS:
				break
		if not options.is_empty():
			var spot: Vector2i = options.pick_random()
			cells.append(spot)
			city[spot] = f.name

# Can a rift for city f go on hex c? 4-"reach" hexes from f, at least 4 from
# every other city, not on ruins, an outpost or impassable land, not on another rift.
func spot_ok(c: Vector2i, f: Faction, reach: int) -> bool:
	var d := HexMap.hex_distance(c, f.city_pos)
	if d < MIN_CITY_DISTANCE or d > reach or not game.passable(c) or c in cells or game.outpost_owner(c) != null:
		return false
	for other in game.factions:
		if other != f and other.is_alive() and HexMap.hex_distance(c, other.city_pos) < MIN_CITY_DISTANCE:
			return false
	for r in game.ruins:
		if r["cell"] == c:
			return false
	return true

# An outpost was just founded on a hidden rift (nobody knew it was there): the
# rift tears open somewhere else instead, by the same rules, for the same city.
# Rifts and outposts never share a hex (Nathan: "outpost?????").
func move(cell: Vector2i) -> void:
	var i := cells.find(cell)
	if i < 0:
		return
	var f := game.faction_named(city.get(cell, ""))
	cells.remove_at(i)
	city.erase(cell)
	if f == null:
		return
	for reach in range(MAX_CITY_DISTANCE, HexMap.COLS + HexMap.ROWS + 2):
		var options: Array[Vector2i] = []
		for row in HexMap.ROWS:
			for col in HexMap.COLS:
				var c := Vector2i(col, row)
				if spot_ok(c, f, reach):
					options.append(c)
		if not options.is_empty():
			var spot: Vector2i = options.pick_random()
			cells.insert(i, spot)
			city[spot] = f.name
			return

# The rifts Sköll can come through now (nothing standing on them).
func free_cells() -> Array[Vector2i]:
	var free: Array[Vector2i] = []
	for r in cells:
		if not game.is_blocked(r) and not game.is_city(r):
			free.append(r)
	return free

# The faction whose city this rift opened toward (null if none, or it fell).
func owner_of(cell: Vector2i) -> Faction:
	return game.faction_named(city.get(cell, ""))

# Fallback if every rift is blocked (or no city had room for one): a free hex
# on the edge of the map, at least MIN_CITY_DISTANCE from every city.
func random_edge_cell() -> Vector2i:
	var options: Array[Vector2i] = []
	for row in HexMap.ROWS:
		for col in HexMap.COLS:
			var c := Vector2i(col, row)
			if col != 0 and col != HexMap.COLS - 1 and row != 0 and row != HexMap.ROWS - 1:
				continue
			if game.is_blocked(c) or game.is_city(c):
				continue
			var far_enough := true
			for f in game.factions:
				if f.city_pos != HexMap.NO_CELL and HexMap.hex_distance(c, f.city_pos) < MIN_CITY_DISTANCE:
					far_enough = false
			if far_enough:
				options.append(c)
	return options.pick_random() if not options.is_empty() else Vector2i(0, 0)
