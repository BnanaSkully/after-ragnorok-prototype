class_name Skoll
extends RefCounted

# Sköll, the wolf who swallowed the sun at Ragnarök. He followed the survivors
# through the void. He warns from WARNING_TURN, arrives at the map edge on
# ARRIVAL_TURN, then walks one hex a turn toward the nearest city and attacks it.
# He can't be killed, only driven back to the edge of the map.
#
# "game" is main.gd: Sköll uses it to see the factions, post messages and end
# the game.

const WARNING_TURN := 10 # howling warnings start on this turn
const ARRIVAL_TURN := 14 # he arrives on this turn
const STRENGTH := 12 # his starting Strength
const SWALLOWED_STRENGTH := 20 # his Strength after swallowing the Sun's Daughter

var game # main.gd
var active := false # false until he arrives
var pos := HexMap.NO_CELL
var strength := STRENGTH

func _init(p_game) -> void:
	game = p_game

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
		pos = random_edge_cell()
		game.add_message("Sköll, the wolf who swallowed the sun, has followed you through the void!")
		return
	var target := nearest_city_to(pos)
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
	var in_the_way: Faction = game.unit_at(best)
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
		for u in game.factions: # every unit inside the city dies, not just the owner's
			if u.unit_alive and u.unit_pos == f.city_pos:
				u.unit_alive = false
				u.unit_pos = HexMap.NO_CELL
		f.city_pos = HexMap.NO_CELL
		f.unit_alive = false
		f.unit_pos = HexMap.NO_CELL
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

# Sköll becomes the sun: much stronger, and the whole map goes dark.
func swallow_daughter() -> void:
	game.daughter.state = SunDaughter.State.SWALLOWED
	game.daughter.holder = null
	strength = SWALLOWED_STRENGTH
	game.add_message("Sköll swallowed %s! He is the sun now (Strength %d), and the world goes dark." % [SunDaughter.NAME, strength])

func attack_unit(f: Faction) -> void:
	var chance: float = game.win_chance(strength, f.strength)
	if randf() < chance:
		game.add_message("Sköll attacked %s's unit and destroyed it (%s)." % [f.name, game.odds_text(chance)])
		pos = f.unit_pos
		f.unit_alive = false
		f.unit_pos = HexMap.NO_CELL
	else:
		game.add_message("%s's unit drove Sköll back! (He had a %s.)" % [f.name, game.odds_text(chance)])
		drive_back()

# The player's unit attacks Sköll.
func attacked_by_player() -> void:
	var player: Faction = game.player
	var chance: float = game.win_chance(player.strength, strength)
	if randf() < chance:
		game.add_message("You drove Sköll back (%s)!" % game.odds_text(chance))
		drive_back()
	else:
		game.add_message("You attacked Sköll and your unit was destroyed (%s)." % game.odds_text(chance))
		player.unit_alive = false
		player.unit_pos = HexMap.NO_CELL

# Sköll can't be killed: losing a fight sends him back to the edge of the map.
func drive_back() -> void:
	pos = random_edge_cell()

# A free hex on the edge of the map, at least 3 hexes from every city.
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

func nearest_city_to(cell: Vector2i) -> Faction:
	var best: Faction = null
	var best_d := 999
	for f in game.factions:
		if f.city_pos != HexMap.NO_CELL and HexMap.hex_distance(cell, f.city_pos) < best_d:
			best_d = HexMap.hex_distance(cell, f.city_pos)
			best = f
	return best
