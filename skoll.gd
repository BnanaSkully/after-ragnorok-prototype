class_name Skoll
extends RefCounted

# Sköll, the wolf who swallowed the sun at Ragnarök. He followed the survivors
# through the void. He warns from WARNING_TURN, arrives at the map edge on
# ARRIVAL_TURN through one of the rifts (chosen at random), hunts the city
# nearest that rift, walks one hex a turn toward it and attacks it.
# He can't be killed, only driven back to the edge of the map.
#
# "game" is the GameState (game_state.gd): Sköll uses it to see the factions, post messages and end
# the game.

const WARNING_TURN := 10 # howling warnings start on this turn
const ARRIVAL_TURN := 14 # he arrives on this turn
const STRENGTH := 12 # his starting Strength
const SWALLOWED_STRENGTH := 20 # his Strength after swallowing the Sun's Daughter

# Rifts in the void: the hexes Sköll can come through. The map is split into
# RIFT_SECTIONS_X x RIFT_SECTIONS_Y sections (3 x 2 = 6) and each section gets
# one rift on a random hex. They're rolled on RIFT_TURN (after the Landing, so
# they can keep away from every city) and stay HIDDEN. On arrival he comes
# through one at random and only that rift is revealed. Each time he's driven
# back the rifts are rolled again, so his next way in is always a surprise.
const RIFT_SECTIONS_X := 3
const RIFT_SECTIONS_Y := 2
const RIFT_TURN := 2 # the turn the rifts are first rolled
const RIFT_MIN_CITY_DISTANCE := 3 # rifts stay at least this far from every city
const SIGHT_RANGE := 2 # fog of war: he only sees this far; a rogue Daughter further away is hidden from him
const SPRINT := 2 # hexes a turn he runs when hunting her in the open (she runs 1)

# The GameState (game_state.gd). A "weak" link: the game keeps this object alive,
# but this object doesn't keep the game alive, so Godot can free both later.
var game: GameState:
	get:
		return _game.get_ref()
var _game: WeakRef
var active := false # false until he arrives
var pos := HexMap.NO_CELL
var strength := STRENGTH
var target: Faction = null # the city he is hunting right now
var rifts: Array[Vector2i] = [] # the current rifts (hidden from the player)
var revealed_rift := HexMap.NO_CELL # the rift he last came through (the only one shown)

func _init(p_game: GameState) -> void:
	_game = weakref(p_game)

# Fog of war: what Sköll can see from where he stands.
func can_see(cell: Vector2i) -> bool:
	return active and HexMap.hex_distance(pos, cell) <= SIGHT_RANGE

func is_at(cell: Vector2i) -> bool:
	return active and cell == pos

func take_turn() -> void:
	if game.turn < WARNING_TURN:
		return
	if game.turn < ARRIVAL_TURN:
		var left: int = ARRIVAL_TURN - game.turn
		game.add_message("Howling in the void... Sköll arrives %s." % ("next turn" if left == 1 else "in %d turns" % left))
		return
	if not active:
		active = true
		come_through_rift()
		game.add_message("Sköll, the wolf who swallowed the sun, tears through a rift! He is hunting %s." % target_text())
		return
	# The Daughter out in the open: if he can smell her, he goes for her.
	var daughter: SunDaughter = game.daughter
	if daughter.is_rogue() and can_see(daughter.pos):
		hunt_daughter(daughter)
		return
	if target == null or not target.is_alive():
		pick_target()
	if target == null:
		return
	if HexMap.is_neighbour(pos, target.city_pos):
		attack_city(target)
		return
	# Step to the neighbouring hex that gets closest to the target city.
	var best := HexMap.NO_CELL
	var best_d := 999
	for c in HexMap.neighbours(pos):
		if game.is_city(c):
			continue
		var d := HexMap.hex_distance(c, target.city_pos)
		if d < best_d:
			best_d = d
			best = c
	if best == HexMap.NO_CELL:
		return
	var in_the_way: Unit = game.unit_at(best)
	if in_the_way:
		attack_unit(in_the_way)
	else:
		pos = best

# Sköll doesn't know who shelters the Daughter. He only finds out after
# the battle, if she turns out to be in the city he attacked.
func attack_city(f: Faction) -> void:
	var defence: int = game.city_defence(f)
	var chance: float = game.win_chance(strength, defence)
	var she_is_here: bool = game.daughter.shelters_with(f)
	if randf() < chance:
		game.add_message("Sköll attacked %s's city (defence %d) and destroyed it (%s)." % [f.name, defence, game.odds_text(chance)])
		pos = f.city_pos
		var inside: Unit = game.unit_at(f.city_pos) # whoever is in the city dies, even an enemy
		if inside:
			inside.faction.remove_unit(inside)
		f.city_pos = HexMap.NO_CELL
		f.units.clear() # with its city gone, the faction's army scatters
		if she_is_here:
			swallow_daughter()
		if f == game.player:
			var how := "and swallowed %s. The world goes dark." % SunDaughter.NAME if she_is_here else "on turn %d." % game.turn
			game.end_game("Your city has fallen", "Sköll devoured your people %s" % how)
	else:
		game.add_message("%s's city (defence %d) drove Sköll back! (He had a %s.)" % [f.name, defence, game.odds_text(chance)])
		drive_back()
		if she_is_here:
			var whose := "your city" if f == game.player else "%s's city" % f.name
			game.end_game("Sköll has found %s" % SunDaughter.NAME,
				"He lost the battle, but now he knows she hides in %s.\nPHASE 3 BEGINS EARLY on turn %d: he will charge there again.\n(Phase 3 is not built yet.)" % [whose, game.turn])

# She's out in the open: he sprints toward her (SPRINT hexes a turn), and if
# he reaches her he swallows her with no battle.
func hunt_daughter(d: SunDaughter) -> void:
	for step in SPRINT:
		if HexMap.is_neighbour(pos, d.pos):
			pos = d.pos
			game.add_message("Sköll caught %s out in the open." % SunDaughter.NAME)
			swallow_daughter()
			return
		var best := HexMap.NO_CELL
		var best_d := HexMap.hex_distance(pos, d.pos)
		for c in HexMap.neighbours(pos):
			if game.is_city(c) or game.is_blocked(c):
				continue
			var dist := HexMap.hex_distance(c, d.pos)
			if dist < best_d:
				best_d = dist
				best = c
		if best == HexMap.NO_CELL:
			break
		pos = best
	game.add_message("Sköll has spotted %s in the open and sprints after her!" % SunDaughter.NAME)

# Sköll becomes the sun: much stronger, and the whole map goes dark.
func swallow_daughter() -> void:
	game.daughter.state = SunDaughter.State.SWALLOWED
	game.daughter.holder = null
	game.daughter.pos = HexMap.NO_CELL
	strength = SWALLOWED_STRENGTH
	game.add_message("Sköll swallowed %s! He is the sun now (Strength %d), and the world goes dark." % [SunDaughter.NAME, strength])

func attack_unit(u: Unit) -> void:
	var chance: float = game.win_chance(strength, u.strength)
	if randf() < chance:
		game.add_message("Sköll attacked %s's unit and destroyed it (%s)." % [u.faction.name, game.odds_text(chance)])
		pos = u.pos
		u.faction.remove_unit(u)
	else:
		game.add_message("%s's unit drove Sköll back! (He had a %s.)" % [u.faction.name, game.odds_text(chance)])
		drive_back()

# A unit (the player's) attacks Sköll.
func attacked_by(u: Unit) -> void:
	var chance: float = game.win_chance(u.strength, strength)
	if randf() < chance:
		game.add_message("You drove Sköll back (%s)!" % game.odds_text(chance))
		drive_back()
	else:
		game.add_message("You attacked Sköll and your unit was destroyed (%s)." % game.odds_text(chance))
		u.faction.remove_unit(u)

# Sköll can't be killed: losing a fight sends him back to the edge of the map.
func drive_back() -> void:
	place_rifts() # new rifts every time he's driven back
	come_through_rift()
	if target:
		game.add_message("Sköll slinks back into the void... and bursts out of another rift, hunting %s." % target_text())

# One rift on a random hex in each section of the map, at least
# RIFT_MIN_CITY_DISTANCE from every standing city.
func place_rifts() -> void:
	rifts.clear()
	for sy in RIFT_SECTIONS_Y:
		for sx in RIFT_SECTIONS_X:
			var options: Array[Vector2i] = []
			for row in range(sy * HexMap.ROWS / RIFT_SECTIONS_Y, (sy + 1) * HexMap.ROWS / RIFT_SECTIONS_Y):
				for col in range(sx * HexMap.COLS / RIFT_SECTIONS_X, (sx + 1) * HexMap.COLS / RIFT_SECTIONS_X):
					var c := Vector2i(col, row)
					var far_enough := true
					for f in game.factions:
						if f.is_alive() and HexMap.hex_distance(c, f.city_pos) < RIFT_MIN_CITY_DISTANCE:
							far_enough = false
					if far_enough:
						options.append(c)
			if not options.is_empty():
				rifts.append(options.pick_random())

# Come out of a random free rift and hunt the city nearest to it.
func come_through_rift() -> void:
	var free: Array[Vector2i] = []
	for r in rifts:
		if not game.is_blocked(r) and not game.is_city(r):
			free.append(r)
	pos = free.pick_random() if not free.is_empty() else random_edge_cell()
	revealed_rift = pos
	pick_target()

# He doesn't know which city hides the Daughter: he hunts the city nearest the
# rift he came through (a tie is decided at random).
func pick_target() -> void:
	var best: Array[Faction] = []
	var best_d := 999
	for f in game.factions:
		if not f.is_alive():
			continue
		var d := HexMap.hex_distance(pos, f.city_pos)
		if d < best_d:
			best_d = d
			best = [f]
		elif d == best_d:
			best.append(f)
	target = best.pick_random() if not best.is_empty() else null

func target_text() -> String:
	if target == null:
		return "nobody"
	return "your city" if target == game.player else "%s's city" % target.name

# Fallback if every rift is blocked: a free hex on the edge of the map, at
# least 3 hexes from every city.
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
				if f.city_pos != HexMap.NO_CELL and HexMap.hex_distance(c, f.city_pos) < 3:
					far_enough = false
			if far_enough:
				options.append(c)
	return options.pick_random() if not options.is_empty() else Vector2i(0, 0)
