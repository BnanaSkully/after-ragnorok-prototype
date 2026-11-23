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
# that sees one remembers it in Faction.known_rifts) or used. They are
# PERMANENT (Nathan, 22 Nov): never rolled again, so a rift once found stays
# on your map for the rest of the game.
#
# Only rules live here (no drawing): main.gd and view_3d.gd read cells and
# revealed to show them.

const RIFT_TURN := 2 # the turn the rifts are first rolled
const MIN_CITY_DISTANCE := 4 # rifts stay at least this far from every city (was 3: he came out one step from a city's walls)
const MAX_CITY_DISTANCE := 7 # ...and at most this far from the city they belong to

# The dangerous season (full rifts step 3, Nathan's pick: a fixed calendar
# "for now"): the roots of Yggdrasil stir and the rifts wake. SEASON_LENGTH
# turns long, every SEASON_EVERY turns from SEASON_FIRST (turns 7-8, 14-15,
# 21-22, 28-29, 35-36; 14 is Sköll's arrival on purpose). A message warns the
# turn before. When it begins, Rift Walkers crawl out (step 4, below);
# travelling between rifts (step 5) will use it too.
const SEASON_NAME := "the Root-tide" # placeholder name
const SEASON_FIRST := 7
const SEASON_EVERY := 7
const SEASON_LENGTH := 2

# Rift Walkers (full rifts step 4, the simple version Nathan picked;
# rift_walker.gd): when the season begins, WALKERS_PER_SEASON crawl out of
# every rift, onto a free hex next to it, up to MAX_WALKERS_PER_RIFT alive
# from each rift. They stay until killed (more come each season). Every turn
# each one may take a step (WANDER_CHANCE), never farther than WANDER_RANGE
# from its rift, never into a city or onto a rift. Each one standing on a
# faction's land costs that faction WALKER_FOOD Food a turn.
const WALKERS_PER_SEASON := 1
const MAX_WALKERS_PER_RIFT := 2
const WANDER_RANGE := 3
const WANDER_CHANCE := 0.5
const WALKER_FOOD := 1
const WALKER_HEAL := 2 # HP it heals in a turn nobody fought it
# The GameState (game_state.gd). A "weak" link: the game keeps this object alive,
# but this object doesn't keep the game alive, so Godot can free both later.
var game: GameState:
	get:
		return _game.get_ref()
var _game: WeakRef
var cells: Array[Vector2i] = [] # the current rifts (hidden until found)
var city := {} # rift hex -> name of the faction whose city that rift opened toward
var revealed := HexMap.NO_CELL # the rift Sköll last came through (shown to whoever sees it)
var walkers: Array[RiftWalker] = [] # the Rift Walkers out on the map

func _init(p_game: GameState) -> void:
	_game = weakref(p_game)

func has(cell: Vector2i) -> bool:
	return cell in cells

# The season's name at the start of a sentence ("The Root-tide").
static func season_title() -> String:
	return SEASON_NAME.left(1).to_upper() + SEASON_NAME.substr(1)

# Is the season on during this turn?
static func season_on(turn: int) -> bool:
	return turn >= SEASON_FIRST and (turn - SEASON_FIRST) % SEASON_EVERY < SEASON_LENGTH

# Turns of the season left, counting this one (0 if it isn't on).
static func season_left(turn: int) -> int:
	if not season_on(turn):
		return 0
	return SEASON_LENGTH - (turn - SEASON_FIRST) % SEASON_EVERY

# The first turn of the next season after this turn.
static func next_season(turn: int) -> int:
	if turn < SEASON_FIRST:
		return SEASON_FIRST
	@warning_ignore("integer_division")
	return SEASON_FIRST + ((turn - SEASON_FIRST) / SEASON_EVERY + 1) * SEASON_EVERY

# The season's messages for the turn just begun: a warning the turn before,
# then when it starts and when it ends.
func announce_season() -> void:
	var t: int = game.turn
	if season_on(t) and not season_on(t - 1):
		game.add_message("%s has begun: the roots of Yggdrasil stir and the rifts glow (%d turns)." % [season_title(), SEASON_LENGTH])
	elif season_on(t - 1) and not season_on(t):
		game.add_message("%s has passed: the rifts sleep until turn %d." % [season_title(), next_season(t)])
	elif season_on(t + 1):
		game.add_message("The ground hums: %s begins next turn." % SEASON_NAME)

# --- Rift Walkers ----------------------------------------------------------
# The Walker standing on this hex, or null.
func walker_at(cell: Vector2i) -> RiftWalker:
	for w in walkers:
		if w.pos == cell:
			return w
	return null

# Food the Walkers on this faction's land cost it this turn.
func walkers_on_land(f: Faction) -> int:
	var n := 0
	for w in walkers:
		if game.territory_owner(w.pos) == f:
			n += 1
	return n

# Can a Walker step onto (or come out on) this hex? Free, not a city, not a rift.
func walker_may_stand(c: Vector2i) -> bool:
	return HexMap.in_bounds(c) and not game.is_blocked(c) and not game.is_city(c) and not has(c)

# The Walkers' part of a turn (GameState.end_turn, after Sköll): the season's
# first turn brings new ones out; the others wander and heal; the player is
# told when one wanders onto their land.
func walkers_turn() -> void:
	var t: int = game.turn
	var old := walkers.duplicate()
	for w in old:
		if not w.acted and w.hp < RiftWalker.MAX_HP:
			w.hp = mini(RiftWalker.MAX_HP, w.hp + WALKER_HEAL)
		w.acted = false
		if randf() < WANDER_CHANCE:
			var options: Array[Vector2i] = []
			for c in HexMap.neighbours(w.pos):
				if walker_may_stand(c) and HexMap.hex_distance(c, w.home) <= WANDER_RANGE:
					options.append(c)
			if not options.is_empty():
				w.pos = options.pick_random()
	if season_on(t) and not season_on(t - 1):
		var seen := 0
		for rift in cells:
			var out := walkers.filter(func(w): return w.home == rift).size()
			for i in mini(WALKERS_PER_SEASON, MAX_WALKERS_PER_RIFT - out):
				var spots: Array[Vector2i] = []
				for c in HexMap.neighbours(rift):
					if walker_may_stand(c):
						spots.append(c)
				if spots.is_empty():
					break
				var w := RiftWalker.new(spots.pick_random(), rift)
				walkers.append(w)
				if game.player.known_rifts.has(rift) or game.player_can_see(w.pos):
					seen += 1
		if seen > 0:
			game.add_message("%s out of the rifts you know: Yggdrasil's rogue army. They never attack first, but each one on your land eats %d Food a turn." % ["A brood crawls" if seen == 1 else "%d broods crawl" % seen, WALKER_FOOD])
	for w in walkers:
		var land: Faction = game.territory_owner(w.pos)
		var whose: String = land.name if land != null else ""
		if land == game.player and w.on_land != whose:
			game.add_message("A brood wandered onto your land: -%d Food a turn while it stays. Attack it to drive it off." % WALKER_FOOD)
		w.on_land = whose

# A Walker killed in a fight.
func remove_walker(w: RiftWalker) -> void:
	walkers.erase(w)

# Forget every rift (a new game's Crossing).
func clear() -> void:
	cells.clear()
	city.clear()
	revealed = HexMap.NO_CELL
	walkers.clear()

# One rift per standing city: a random hex MIN_CITY_DISTANCE to
# MAX_CITY_DISTANCE from that city and at least MIN_CITY_DISTANCE from every
# other city. Done once, on RIFT_TURN.
func place() -> void:
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
