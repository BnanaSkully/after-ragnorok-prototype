extends SceneTree
const H := preload("res://tests/helpers.gd")
const Buildings := preload("res://buildings.gd")
# City buildings: each one's effect exactly, then 300 games: do they soak up
# the Industry that used to pile up? (Industry stored by the AIs on turn 15.)
func new_game():
	var m = load("res://main.tscn").instantiate()
	root.add_child(m)
	var s = m.state
	for step in 4: s.choose(s.Crossing.EVENTS[step]["choices"][0]["effects"])
	H.flatten(s); s.start_landing(); s.try_land(Vector2i(6, 4))
	return m

func _initialize() -> void:
	await process_frame
	seed(9)
	var m = new_game(); var s = m.state; var p = s.player
	p.industry = 100
	var before := {"food": s.food_change(p), "industry": s.industry_change(p), "defence": s.city_defence(p), "sight": s.city_sight(p), "strength": p.strength}
	for key in Buildings.LIST: s.player_build_building(key)
	print("1. built all four, Industry 100 -> %d (expect %d)" % [p.industry, 100 - 8 - 12 - 6 - 10])
	print("   Food a turn %+d (Granary, expect +2), Industry %+d (Workshop, expect +2), defence %+d and sight %+d (Watchtower, expect +1, +2), new army Strength %d -> %d (Forge)" % [s.food_change(p) - before["food"], s.industry_change(p) - before["industry"], s.city_defence(p) - before["defence"], s.city_sight(p) - before["sight"], before["strength"], p.strength])
	s.player_build_unit()
	print("   an army built after the Forge has Strength %d; the old one still %d" % [p.units[-1].strength, p.units[0].strength])
	var ind = p.industry
	s.player_build_building("granary")
	print("2. building the Granary twice: Industry unchanged=%s (expect true)" % (p.industry == ind))
	m.queue_free()
	var n_games: int = H.games(300)
	var stored := 0.0; var built := 0.0; var bad := {}; var ends := {}
	for g in n_games:
		m = load("res://main.tscn").instantiate()
		root.add_child(m)
		s = m.state
		for step in 4: s.choose(s.Crossing.EVENTS[step]["choices"][(g >> step) & 1]["effects"])
		s.start_landing()
		var spots = H.landing_spots(s)
		s.try_land(spots[(g * 7) % spots.size()])
		while not s.game_over:
			H.answer_choices(s)
			if s.food_change(s.player) > 0: s.player_build_unit()
			for key in Buildings.LIST: s.player_build_building(key)
			s.end_turn()
			if s.has_pending_offer(): s.pending_relation().answer(false)
			if s.turn == 15:
				for f in s.ais:
					stored += f.industry / (3.0 * n_games); built += f.buildings.size() / (3.0 * n_games)
			for f in s.factions:
				if f.industry < 0 or f.food < 0: bad["negative stores"] = 1
			if s.turn > 60: bad["game never ended"] = 1; break
		ends[s.end_title] = ends.get(s.end_title, 0) + 1
		m.queue_free()
	print("3. %d games: on turn 15 each AI has %.1f buildings and %.1f Industry stored" % [n_games, built, stored])
	print("Endings: %s" % ends)
	print("Impossible states: %s" % (bad if bad.size() > 0 else "none"))
	quit()
