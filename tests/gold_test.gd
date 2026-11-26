extends SceneTree
const H := preload("res://tests/helpers.gd")
const Buildings := preload("res://buildings.gd")
# Gold and the upkeep switch (GDD 24 Nov: "armies cost Gold, Food only grows
# cities"). Each rule on a set-up game, then 300 games for numbers and
# impossible states: Gold never ends a turn below 0, armies never eat Food.
func new_game():
	var m = load("res://main.tscn").instantiate()
	root.add_child(m)
	var s = m.state
	for step in 4: s.choose(s.Crossing.EVENTS[step]["choices"][0]["effects"])
	H.flatten(s); s.start_landing(); s.try_land(Vector2i(6, 4))
	return m

func has_part(parts: Array, what: String) -> bool:
	for p in parts:
		if p[0] == what: return true
	return false

func _initialize() -> void:
	await process_frame
	seed(11)
	var m = new_game(); var s = m.state; var p = s.player
	print("1. Gold at the Landing: you %d, each AI %s (expect %d)" % [p.gold, s.ais.map(func(f): return f.gold), GameState.START_GOLD])
	# you start with 1 army and 1 scout at population 1: 2 - 2 - 1 = -1 a turn
	print("2. Gold a turn at the start: %+d (expect city %d - army %d - scout %d = %+d); parts %s" % [s.gold_change(p), GameState.CITY_GOLD, GameState.ARMY_GOLD, GameState.SCOUT_GOLD, GameState.CITY_GOLD - GameState.ARMY_GOLD - GameState.SCOUT_GOLD, s.gold_parts(p)])
	print("3. armies no longer eat Food: 'armies eat' in the Food breakdown=%s (expect false); Industry breakdown has upkeep=%s (expect false)" % [has_part(s.food_parts(p), "armies eat"), has_part(s.industry_parts(p), "army upkeep")])
	p.population = 4
	print("4. population 4 adds %+d Gold (expect +2: one per %d)" % [s.gold_change(p) - (GameState.CITY_GOLD - GameState.ARMY_GOLD - GameState.SCOUT_GOLD), GameState.POP_PER_GOLD])
	p.population = 1
	p.industry = 100
	var g0: int = s.gold_change(p)
	s.player_build_building("market")
	print("5. Market: Gold a turn %+d -> %+d (expect +%d), Industry 100 -> %d (expect %d)" % [g0, s.gold_change(p), Buildings.MARKET_GOLD, p.industry, 100 - Buildings.cost("market")])
	# run out of Gold: build armies until upkeep outruns income, empty the store, end the turn
	for i in 3: s.player_build_unit()
	var armies: int = s.army_count(p); var scouts: int = p.scout_count()
	p.gold = 0
	var change: int = s.gold_change(p)
	H.answer_choices(s)
	s.end_turn()
	if s.has_pending_offer(): s.pending_relation().answer(false)
	print("6. out of Gold (%+d a turn): armies %d -> %d (expect one fewer), scouts %d -> %d (expect the same), Gold %d (expect 0)" % [change, armies, s.army_count(p), scouts, p.scout_count(), p.gold])
	# no armies left: then a scout goes
	for u in p.units.duplicate():
		if not u.is_scout(): p.remove_unit(u)
	p.buildings.erase("market")
	p.gold = 0
	var scouts_before: int = p.scout_count()
	var change2: int = s.gold_change(p)
	s.end_turn()
	if s.has_pending_offer(): s.pending_relation().answer(false)
	print("7. only scouts and %+d Gold a turn: scouts %d -> %d (expect %s)" % [change2, scouts_before, p.scout_count(), "one fewer" if change2 < 0 else "the same"])
	m.queue_free()

	var n_games: int = H.games(300)
	var st := {"your Gold on turn 20": 0.0, "your armies on turn 20": 0.0, "AI armies on turn 20": 0.0, "AI Gold on turn 20": 0.0, "AI Markets on turn 20": 0.0, "desertions a game (you)": 0.0, "desertions a game (AIs)": 0.0}
	var bad := {}; var ends := {}
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
			if s.gold_change(s.player) >= GameState.ARMY_GOLD: s.player_build_unit()
			for key in Buildings.LIST: s.player_build_building(key)
			s.messages.clear()
			s.end_turn()
			if s.has_pending_offer(): s.pending_relation().answer(false)
			for line in s.messages:
				if "ran out of Gold" in line:
					if line.begins_with("You"): st["desertions a game (you)"] += 1.0 / n_games
					else: st["desertions a game (AIs)"] += 1.0 / n_games
			if s.turn == 20:
				st["your Gold on turn 20"] += s.player.gold / float(n_games)
				st["your armies on turn 20"] += s.army_count(s.player) / float(n_games)
				for f in s.ais:
					st["AI armies on turn 20"] += s.army_count(f) / (3.0 * n_games)
					st["AI Gold on turn 20"] += f.gold / (3.0 * n_games)
					st["AI Markets on turn 20"] += (1.0 if f.buildings.has("market") else 0.0) / (3.0 * n_games)
			for f in s.factions:
				if f.gold < 0: bad["Gold below 0 after a turn"] = 1
				if f.industry < 0 or f.food < 0: bad["negative stores"] = 1
				if has_part(s.food_parts(f), "armies eat"): bad["armies eat Food"] = 1
			if s.turn > 60: bad["game never ended"] = 1; break
		ends[s.end_title] = ends.get(s.end_title, 0) + 1
		m.queue_free()
	for k in st: print("   %s: %.2f" % [k, st[k]])
	print("Endings: %s" % ends)
	print("Impossible states: %s" % (bad if bad.size() > 0 else "none"))
	quit()
