extends SceneTree
const H := preload("res://tests/helpers.gd")

# Full rifts step 4: Rift Walkers (rift_walker.gd, Rifts.WALKERS_*). Part 1:
# each rule on a set-up game. Part 2: whole 40-turn games with a passive
# player: how many come out, how much Food they cost, how many die, and no
# impossible states. Run: godot --headless --script tests/walker_test.gd

func new_game():
	var m = load("res://main.tscn").instantiate()
	root.add_child(m)
	var s = m.state
	for step in 4: s.choose(s.Crossing.EVENTS[step]["choices"][0]["effects"])
	H.flatten(s); s.start_landing(); s.try_land(Vector2i(6, 4))
	return m

func play_turn(s) -> void:
	H.answer_choices(s)
	s.end_turn()
	if s.has_pending_offer(): s.pending_relation().answer(false)
	H.answer_choices(s)
	if s.has_pending_offer(): s.pending_relation().answer(false)

# Anything a Walker must never do (checked at the end of every turn).
func problems(s) -> Array[String]:
	var bad: Array[String] = []
	var seen := {}
	for w in s.rifts.walkers:
		if s.is_city(w.pos): bad.append("walker in a city")
		if s.rifts.has(w.pos): bad.append("walker on a rift")
		if s.unit_at(w.pos) != null: bad.append("walker on a unit")
		if s.skoll.is_at(w.pos): bad.append("walker under Sköll")
		if not s.passable(w.pos): bad.append("walker on water/mountain")
		if seen.has(w.pos): bad.append("two walkers on a hex")
		seen[w.pos] = true
		if HexMap.hex_distance(w.pos, w.home) > Rifts.WANDER_RANGE: bad.append("walker strayed from its rift")
		if w.hp <= 0 or w.hp > RiftWalker.MAX_HP: bad.append("walker HP %d" % w.hp)
	for rift in s.rifts.cells:
		if s.rifts.walkers.filter(func(w): return w.home == rift).size() > Rifts.MAX_WALKERS_PER_RIFT: bad.append("too many walkers from one rift")
	return bad

func _initialize() -> void:
	await process_frame
	seed(7)
	var m = new_game(); var s = m.state
	while s.turn < Rifts.SEASON_FIRST - 1: play_turn(s)
	print("1. turn %d (the turn before the season): walkers %d (expect 0)" % [s.turn, s.rifts.walkers.size()])
	play_turn(s)
	var beside = s.rifts.walkers.filter(func(w): return HexMap.is_neighbour(w.pos, w.home)).size()
	print("   turn %d (season begins): walkers %d (expect %d, one per rift), next to their rift %d" % [s.turn, s.rifts.walkers.size(), s.rifts.cells.size(), beside])
	play_turn(s)
	print("   turn %d (season's 2nd turn): walkers %d (expect still %d: they come only when it begins)" % [s.turn, s.rifts.walkers.size(), s.rifts.cells.size()])
	print("   problems: %s" % [problems(s)])
	# 2. on your land: -1 Food each, in the breakdown
	var w: RiftWalker = s.rifts.walkers[0]
	var food0: int = s.food_change(s.player)
	w.pos = Vector2i(7, 4) # next to your city at (6, 4): your land
	var parts: Array = s.food_parts(s.player).filter(func(p): return "Walker" in p[0])
	print("2. a walker on your land: Food a turn %d -> %d (expect -%d), breakdown %s" % [food0, s.food_change(s.player), Rifts.WALKER_FOOD, parts])
	# 3. it blocks: nothing can step there; it never attacks first
	print("3. its hex is blocked=%s (expect true)" % s.is_blocked(w.pos))
	H.answer_choices(s)
	for u in s.player.units.duplicate():
		s.player.remove_unit(u)
	var guard = s.player.add_unit(Vector2i(8, 4)) # next to the walker
	guard.hp = Unit.MAX_HP
	var trust0: Array = s.relations.map(func(r): return r.trust)
	var hp0: int = guard.hp
	s.rifts.walkers_turn() # a Walker turn: it may wander but never attack
	print("   a unit next to it after its turn: HP %d -> %d (expect no change: it never attacks first)" % [hp0, guard.hp])
	# 4. attacking it: an HP fight, no war
	w.pos = Vector2i(7, 4); w.hp = RiftWalker.MAX_HP
	guard.pos = Vector2i(8, 4); guard.moves = 1
	var war_target = s.war_target(w.pos)
	var wars0: int = s.relations.filter(func(r): return r.at_war).size()
	s.player_unit_act(guard, w.pos)
	var wars: int = s.relations.filter(func(r): return r.at_war).size()
	print("4. your unit attacks it: walker HP %d, your unit HP %d (both expect under 10), war target %s (expect null), wars %d -> %d (expect no change), Trust unchanged=%s" % [w.hp, guard.hp, war_target, wars0, wars, trust0 == s.relations.map(func(r): return r.trust)])
	var tries := 0
	while w in s.rifts.walkers and tries < 10:
		var x = s.unit_at(Vector2i(8, 4))
		if x == null: x = s.player.add_unit(Vector2i(8, 4))
		x.moves = 1; x.hp = Unit.MAX_HP; x.strength = 6
		s.player_unit_act(x, w.pos)
		tries += 1
	print("   attacked until it dies: dead=%s after %d more attacks; the killer moved in=%s" % [not w in s.rifts.walkers, tries, s.unit_at(Vector2i(7, 4)) != null])
	# 5. an AI army next to a walker on its own land attacks it
	var jp = s.ais[0]
	var w2: RiftWalker = s.rifts.walkers[0] if not s.rifts.walkers.is_empty() else null
	if w2 != null:
		var spot := HexMap.NO_CELL
		for c in HexMap.neighbours(jp.city_pos):
			if not s.is_blocked(c) and not s.is_city(c):
				spot = c
				break
		w2.pos = spot; w2.hp = RiftWalker.MAX_HP
		var ai_u = jp.units.filter(func(u): return not u.is_scout())[0]
		ai_u.pos = jp.city_pos; ai_u.hp = Unit.MAX_HP
		s.ai_take_turn(jp)
		print("5. a walker next to the %s city: attacked by its army=%s (expect true)" % [jp.name, w2.hp < RiftWalker.MAX_HP or not w2 in s.rifts.walkers])
	# 6. the next season brings more, up to the cap per rift
	while s.turn < Rifts.SEASON_FIRST + Rifts.SEASON_EVERY * 3 and not s.game_over: play_turn(s)
	var most := 0
	for rift in s.rifts.cells:
		most = maxi(most, s.rifts.walkers.filter(func(x): return x.home == rift).size())
	print("6. turn %d: walkers %d, most from one rift %d (at most %d); problems %s" % [s.turn, s.rifts.walkers.size(), most, Rifts.MAX_WALKERS_PER_RIFT, problems(s)])
	m.queue_free()

	# Part 2: whole games, a passive player
	var n_games: int = H.games(300)
	var st := {"walkers out on turn 20": 0.0, "walkers out on turn 40": 0.0, "walkers came out": 0.0, "walkers killed": 0.0, "your Food lost to them": 0.0, "AI Food lost to them (each)": 0.0, "turns one was on your land": 0.0}
	var ends := {}
	var bad := {}
	for g in n_games:
		seed(1000 + g)
		m = new_game(); s = m.state
		var known := {}
		while not s.game_over and s.turn < GameState.END_TURN:
			play_turn(s)
			var now := {}
			for x in s.rifts.walkers:
				now[x] = true
				if not known.has(x): st["walkers came out"] += 1
			for x in known:
				if not now.has(x): st["walkers killed"] += 1
			known = now
			var mine: int = s.rifts.walkers_on_land(s.player)
			st["your Food lost to them"] += mine * Rifts.WALKER_FOOD
			if mine > 0: st["turns one was on your land"] += 1
			for f in s.ais:
				st["AI Food lost to them (each)"] += s.rifts.walkers_on_land(f) * Rifts.WALKER_FOOD / 3.0
			if s.turn == 20: st["walkers out on turn 20"] += s.rifts.walkers.size()
			for p in problems(s): bad[p] = bad.get(p, 0) + 1
		if s.turn >= GameState.END_TURN: st["walkers out on turn 40"] += s.rifts.walkers.size()
		ends[s.end_title] = ends.get(s.end_title, 0) + 1
		m.queue_free()
		await process_frame
	print("Part 2, %d games, per game: %s" % [n_games, ", ".join(st.keys().map(func(k): return "%s %.2f" % [k, st[k] / n_games]))])
	print("Endings: %s" % ends)
	print("Impossible states: %s" % (bad if bad.size() > 0 else "none"))
	quit()
