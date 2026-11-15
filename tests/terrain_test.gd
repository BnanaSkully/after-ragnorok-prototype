extends SceneTree
const H := preload("res://tests/helpers.gd")

# Terrain: maps are always connected, cities sit on open land, and the rules
# (move costs, defence, outpost income, paths around lakes) work exactly.

func new_game():
	var m = load("res://main.tscn").instantiate()
	root.add_child(m)
	return m

func _initialize() -> void:
	await process_frame
	seed(11)
	# 1. 300 maps
	var counts := [0, 0, 0, 0, 0]; var bad := {}
	for g in 300:
		var m = new_game(); var s = m.state
		for c in s.terrain: counts[s.terrain[c]] += 1
		if not Terrain.all_connected(s.terrain): bad["not connected"] = bad.get("not connected", 0) + 1
		for f in s.ais:
			if s.terrain_at(f.city_pos) != Terrain.Type.PLAINS: bad["AI city not on plains"] = 1
			for n in HexMap.neighbours(f.city_pos):
				if not s.passable(n): bad["AI city hemmed in"] = 1
		if H.landing_spots(s).size() < 20: bad["fewer than 20 landing hexes"] = bad.get("fewer than 20 landing hexes", 0) + 1
		m.queue_free()
	var total := 0
	for n in counts: total += n
	print("1. 300 maps: %s; problems: %s" % [", ".join(range(5).map(func(t): return "%s %d%%" % [Terrain.NAMES[t], roundi(100.0 * counts[t] / total)])), bad if bad.size() > 0 else "none"])
	# 2. rules on a hand-made map
	var m = new_game(); var s = m.state
	H.flatten(s)
	for step in 4: s.choose(s.Crossing.EVENTS[step]["choices"][0]["effects"])
	s.start_landing(); s.try_land(Vector2i(6, 4))
	var scout = s.player.units.filter(func(u): return u.is_scout())[0]
	scout.pos = Vector2i(6, 6); scout.moves = 2
	s.terrain[Vector2i(7, 6)] = Terrain.Type.FOREST
	s.terrain[Vector2i(5, 6)] = Terrain.Type.WATER
	print("2. scout, 2 moves: into water=%s (expect false)" % s.player_unit_act(scout, Vector2i(5, 6)))
	print("   into forest=%s, moves left %d (expect true, 0)" % [s.player_unit_act(scout, Vector2i(7, 6)), scout.moves])
	scout.moves = 2; s.player_unit_act(scout, Vector2i(8, 6))
	s.terrain[Vector2i(9, 6)] = Terrain.Type.HILLS
	print("   after a plains step (1 move left), into hills=%s (expect false: needs 2)" % s.player_unit_act(scout, Vector2i(9, 6)))
	var army = s.player.units.filter(func(u): return not u.is_scout())[0]
	army.pos = Vector2i(8, 7); army.moves = 1
	s.terrain[Vector2i(9, 7)] = Terrain.Type.HILLS
	print("   army with its 1 full move, into hills=%s (expect true: a full move always allows one step)" % s.player_unit_act(army, Vector2i(9, 7)))
	# 3. defence
	var greek = s.ais[2]
	var gu = greek.units[0]; gu.pos = Vector2i(10, 7)
	for t in [Terrain.Type.PLAINS, Terrain.Type.FOREST, Terrain.Type.HILLS]:
		s.terrain[gu.pos] = t
		print("3. attacking Strength 3 into %s: defender counts as %d, odds %s" % [Terrain.NAMES[t], s.defender_strength(gu), s.odds_text(s.win_chance(3, s.defender_strength(gu)))])
	# 4. outpost income by land
	s.player.outposts.clear()
	var f0: int = s.food_change(s.player); var i0: int = s.industry_change(s.player)
	for t in [Terrain.Type.PLAINS, Terrain.Type.FOREST, Terrain.Type.HILLS]:
		s.terrain[Vector2i(3, 1)] = t
		s.player.outposts.clear(); s.player.outposts.append(Vector2i(3, 1))
		print("4. outpost on %s: Food %+d, Industry %+d" % [Terrain.NAMES[t], s.food_change(s.player) - f0, s.industry_change(s.player) - i0])
	s.player.outposts.clear()
	# 5. a path around a lake
	H.flatten(s)
	for c in [Vector2i(4, 8), Vector2i(4, 9), Vector2i(4, 10), Vector2i(4, 7)]: s.terrain[c] = Terrain.Type.WATER
	var walker = s.player.units[0]; walker.pos = Vector2i(2, 9)
	var steps := 0; var path := [walker.pos]
	while walker.pos != Vector2i(6, 9) and steps < 12:
		var nxt = s.step_toward(walker.pos, Vector2i(6, 9))
		if nxt == HexMap.NO_CELL: break
		walker.pos = nxt; path.append(nxt); steps += 1
	print("5. walking (2,9) -> (6,9) round a lake: arrived=%s in %d steps, never in water=%s" % [walker.pos == Vector2i(6, 9), steps, path.all(func(c): return s.passable(c))])
	m.queue_free()
	quit()
