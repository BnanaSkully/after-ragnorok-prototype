extends SceneTree
const H := preload("res://tests/helpers.gd")
const Buildings := preload("res://buildings.gd")

# The army snowball (Nathan's playtest: 17 units, Strength 100 by turn 20).
# A "strong player" builds an army whenever it can afford one and has room,
# otherwise city buildings and walls; it marches armies out of the city to
# make room, and attacks Sköll whenever he stands next to one of its armies.
# Reports on turn 20: units, army Strength, Food and Industry, and how Sköll
# fared (did he take cities, how often was he driven back).

var st := {}
var threat := {"his odds against your city": 0.0, "your armies drive him off": 0.0, "games": 0.0}
func strong_turn(s) -> void:
	var p = s.player
	H.answer_choices(s)
	# march non-garrison armies one step away from the city, inside lands we may use
	for u in p.units.duplicate():
		if not u in p.units or u.is_scout() or u.pos == p.city_pos or u.moves <= 0: continue
		if s.skoll.active and HexMap.is_neighbour(u.pos, s.skoll.pos):
			s.player_unit_act(u, s.skoll.pos) # fight the wolf
			st["your attacks on Sköll"] += 1
			continue
		var out = HexMap.neighbours(u.pos).filter(func(c): return s.passable(c) and s.unit_at(c) == null and not s.is_city(c) and s.war_target(c) == null and HexMap.hex_distance(c, p.city_pos) > HexMap.hex_distance(u.pos, p.city_pos) and HexMap.hex_distance(c, p.city_pos) <= 3)
		if not out.is_empty(): s.player_unit_act(u, out.pick_random())
	# the scout explores (to find outpost spots and ruins)
	for u in p.units.duplicate():
		if not u in p.units or not u.is_scout(): continue
		while u in p.units and u.moves > 0 and not s.is_waiting():
			var goal = s.nearest_unexplored(p, u.pos)
			if goal == HexMap.NO_CELL: break
			var step = s.step_toward(u.pos, goal, p)
			if step == HexMap.NO_CELL or not s.player_unit_act(u, step): break
		H.answer_choices(s)
	# build, like a player who wants a big army: outposts (plains first: Food),
	# a Granary, then armies while Food stays positive, then everything else
	for i in 2:
		var spots = s.outpost_spots(p)
		if spots.is_empty() or p.industry < GameState.OUTPOST_COST: break
		spots.sort_custom(func(a, b): return Terrain.OUTPOST_FOOD[s.terrain_at(a)] > Terrain.OUTPOST_FOOD[s.terrain_at(b)])
		s.player_build_outpost(spots[0])
	s.player_build_building("granary")
	for i in 4:
		if s.food_change(p) - GameState.UNIT_FOOD_UPKEEP < 0: break
		var before: int = p.units.size()
		s.player_build_unit()
		if p.units.size() == before: break
	for key in Buildings.LIST: s.player_build_building(key)
	if p.walls < GameState.MAX_WALLS: s.player_build_walls()
	H.answer_choices(s)

func _initialize() -> void:
	await process_frame
	seed(20)
	var n_games: int = H.games(200)
	st = {"city defence on turn 14": 0.0, "Sköll attacks on your city": 0.0, "Sköll attacks on your armies": 0.0, "your attacks on Sköll": 0.0, "armies": 0.0, "army strength": 0.0, "food": 0.0, "industry": 0.0, "ai armies": 0.0, "Sköll driven back": 0.0, "units lost to Sköll": 0.0}
	var dist := {}
	var ends := {}; var bad := {}
	for g in n_games:
		var m = load("res://main.tscn").instantiate()
		root.add_child(m)
		var s = m.state
		for step in 4: s.choose(s.Crossing.EVENTS[step]["choices"][(g >> step) & 1]["effects"])
		s.start_landing()
		var spots = H.landing_spots(s)
		s.try_land(spots[(g * 7) % spots.size()])
		var last_armies := 0
		while not s.game_over:
			strong_turn(s)
			s.messages.clear()
			s.end_turn()
			if s.has_pending_offer(): s.pending_relation().answer(randf() < 0.5)
			if s.turn == Skoll.ARRIVAL_TURN: st["city defence on turn 14"] += s.city_defence(s.player)
			if s.turn == 19 and s.player.is_alive():
				# if Sköll (Strength 12) came now: his odds against your city, and the
				# odds that your armies, each attacking him once, drive him off
				var miss := 1.0
				for u in s.player.units:
					if not u.is_scout():
						var mine: int = u.fighting_strength() if u.has_method("fighting_strength") else u.strength
						miss *= 1.0 - s.win_chance(mine, Skoll.STRENGTH)
				threat["his odds against your city"] += s.win_chance(Skoll.STRENGTH, s.city_defence(s.player))
				threat["your armies drive him off"] += 1.0 - miss
				threat["games"] += 1
			for msg in s.messages:
				if msg.begins_with("Sköll attacked Norse's city") or msg.begins_with("Norse's city (defence"): st["Sköll attacks on your city"] += 1
				if msg.begins_with("Sköll attacked Norse's unit") or msg.begins_with("Norse's unit held"): st["Sköll attacks on your armies"] += 1
				if "slinks back into the void" in msg: st["Sköll driven back"] += 1
				if msg.begins_with("Sköll attacked Norse") and ("destroyed it" in msg or "killed" in msg): st["units lost to Sköll"] += 1
			for f in s.factions:
				if f.food < 0 or f.industry < 0: bad["negative stores"] = 1
				for u in f.units:
					if "hp" in u and (u.hp <= 0 or u.hp > u.MAX_HP): bad["unit HP out of range"] = 1
			last_armies = s.player.units.filter(func(u): return not u.is_scout()).size()
			if s.turn > 40: bad["game never ended"] = 1; break
		st["armies"] += last_armies; st["army strength"] += s.army_power(s.player)
		st["food"] += s.player.food; st["industry"] += s.player.industry
		dist[last_armies] = dist.get(last_armies, 0) + 1
		for f in s.ais: st["ai armies"] += f.units.filter(func(u): return not u.is_scout()).size() / 3.0
		ends[s.end_title] = ends.get(s.end_title, 0) + 1
		m.queue_free()
	var keys = dist.keys(); keys.sort()
	print("Strong player, %d games, at the end of the game (turn 40 or when it ended), per game: %s" % [n_games, ", ".join(st.keys().map(func(k): return "%s %.1f" % [k, st[k] / n_games]))])
	print("If Sköll came on turn 19 (%d games): his odds against your city %d%%; your armies, each attacking once, drive him off %d%%" % [threat["games"], roundi(100 * threat["his odds against your city"] / threat["games"]), roundi(100 * threat["your armies drive him off"] / threat["games"])])
	print("Armies at the end: %s" % ", ".join(keys.map(func(k): return "%d: %d" % [k, dist[k]])))
	print("Endings: %s" % ends)
	print("Impossible states: %s" % (bad if bad.size() > 0 else "none"))
	quit()
