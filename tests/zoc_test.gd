extends SceneTree
const H := preload("res://tests/helpers.gd")

# Zone of control (standard 4X).
# Part 1: each rule on a set-up game (flat map). Part 2: full games, with the
# rule on and off, to measure what it changes.

func new_game():
	var m = load("res://main.tscn").instantiate()
	root.add_child(m)
	var s = m.state
	for step in 4: s.choose(s.Crossing.EVENTS[step]["choices"][0]["effects"])
	H.flatten(s); s.start_landing()
	s.try_land(Vector2i(6, 4))
	H.answer_choices(s)
	return m

# Hexes next to both a and b.
func shared(a: Vector2i, b: Vector2i) -> Array:
	return HexMap.neighbours(a).filter(func(c): return HexMap.is_neighbour(c, b))

# A hex next to a but 2+ away from b.
func away(a: Vector2i, b: Vector2i) -> Vector2i:
	for c in HexMap.neighbours(a):
		if HexMap.hex_distance(c, b) >= 2:
			return c
	return HexMap.NO_CELL

# Only these units left on the map (everyone else's removed).
func keep_only(s, keep: Array) -> void:
	for f in s.factions:
		for u in f.units.duplicate():
			if not u in keep: f.remove_unit(u)

func _initialize() -> void:
	await process_frame
	seed(31)
	var bad := 0
	# 1. Player army next to a Japanese army, at war
	var m = new_game(); var s = m.state; var jp = s.ais[0]
	var x := Vector2i(7, 8); var j := Vector2i(8, 8)
	var p = s.player.units[0]; var ja = jp.units[0]
	keep_only(s, [p, ja])
	p.pos = x; ja.pos = j
	s.relation(jp).rival_declare_war("test")
	print("set-up: land at %s is %s's, at war=%s" % [x, s.territory_owner(x).name if s.territory_owner(x) else "nobody", s.at_war(s.player, jp)])
	var side: Vector2i = shared(x, j)[0]
	p.moves = 1
	var ok = s.player_unit_act(p, side)
	print("1. step past it (to %s, also next to it): allowed=%s, stayed=%s (expect false, true)" % [side, ok, p.pos == x])
	print("   message: %s" % " ".join(s.messages))
	if ok: bad += 1
	p.moves = 1
	ok = s.player_unit_act(p, away(x, j))
	print("2. step away from it: allowed=%s (expect true)" % ok)
	if not ok: bad += 1
	p.pos = x; p.moves = 1
	var hp_before = ja.hp
	ok = s.player_unit_act(p, j)
	print("3. attack it: allowed=%s, it lost %d HP (expect true)" % [ok, hp_before - ja.hp])
	if not ok: bad += 1
	m.queue_free()

	# 4. At peace: no zone of control
	m = new_game(); s = m.state; jp = s.ais[0]
	p = s.player.units[0]; ja = jp.units[0]
	keep_only(s, [p, ja]); p.pos = x; ja.pos = j; p.moves = 1
	ok = s.player_unit_act(p, shared(x, j)[0])
	print("4. at peace, step past their army: allowed=%s (expect true)" % ok)
	if not ok: bad += 1
	m.queue_free()

	# 5. A scout (2 moves) stepping next to an enemy army stops there
	m = new_game(); s = m.state; jp = s.ais[0]
	ja = jp.units[0]
	var sc = s.player.units.filter(func(u): return u.is_scout())[0]
	keep_only(s, [sc, ja]); s.relation(jp).rival_declare_war("test")
	ja.pos = j; sc.pos = Vector2i(6, 8); sc.moves = 2
	ok = s.player_unit_act(sc, Vector2i(7, 8))
	print("5. scout steps next to an enemy army: allowed=%s, moves left %d (expect true, 0)" % [ok, sc.moves])
	if not ok or sc.moves != 0: bad += 1
	# 6. an enemy SCOUT holds nothing
	var js = jp.units.filter(func(u): return u.is_scout())
	if js.is_empty():
		s.build_scout(jp); js = jp.units.filter(func(u): return u.is_scout())
	jp.remove_unit(ja); js[0].pos = j
	sc.pos = Vector2i(6, 8); sc.moves = 2
	s.player_unit_act(sc, Vector2i(7, 8))
	print("6. scout next to an enemy SCOUT: moves left %d (expect 1)" % sc.moves)
	if sc.moves != 1: bad += 1
	m.queue_free()

	# 7. Stepping into your own city is always allowed
	m = new_game(); s = m.state; jp = s.ais[0]
	p = s.player.units[0]; ja = jp.units[0]
	keep_only(s, [p, ja]); s.relation(jp).rival_declare_war("test")
	var city: Vector2i = s.player.city_pos
	var pn: Vector2i = HexMap.neighbours(city)[0]
	var jn: Vector2i = shared(pn, city)[0]
	p.pos = pn; ja.pos = jn; p.moves = 1
	ok = s.player_unit_act(p, city)
	print("7. next to an enemy army, step into your own city (also next to it): allowed=%s (expect true)" % ok)
	if not ok: bad += 1

	# 8. The AI obeys it: a hurt Japanese army (won't attack your walled city)
	# next to your garrison, with your outpost on a hex next to both. With the
	# rule it never takes the outpost or slides round the city; without, it does.
	for on in [true, false]:
		s.zoc_on = on
		var grabbed := 0; var slid := 0
		for i in 200:
			p.pos = city; ja.pos = jn; ja.hp = 5; ja.moves = 1
			s.player.walls = 2
			var post: Vector2i = shared(jn, city).filter(func(c): return c != pn)[0] if shared(jn, city).size() > 1 else pn
			if not post in s.player.outposts: s.player.outposts.append(post)
			s.ai_take_turn(jp)
			if ja.pos == post: grabbed += 1
			elif ja.pos != jn and HexMap.is_neighbour(ja.pos, city): slid += 1
			if post in jp.outposts:
				jp.outposts.erase(post); s.player.outposts.append(post)
		print("8. zone of control %s, 200 AI turns: took your outpost %d, slid round your city %d%s" % ["ON " if on else "OFF", grabbed, slid, " (expect 0, 0)" if on else " (more than 0 shows the test can see it)"])
		if on and grabbed + slid > 0: bad += 1
	s.zoc_on = true
	# 9. AI paths go round: step_toward never picks a hex the rule forbids
	var wrong := 0
	for i in 300:
		ja.pos = Vector2i(randi_range(2, 12), randi_range(2, 8))
		p.pos = HexMap.neighbours(ja.pos).pick_random()
		if s.is_city(p.pos) or s.is_city(ja.pos): continue
		var step = s.step_toward(ja.pos, Vector2i(randi_range(0, 14), randi_range(0, 10)), jp)
		if step != HexMap.NO_CELL and s.zoc_blocks(jp, ja.pos, step): wrong += 1
	print("9. 300 AI paths starting next to your army: forbidden first steps %d (expect 0)" % wrong)
	if wrong > 0: bad += 1
	m.queue_free()
	print("Rule checks: %d problems (expect 0)" % bad)

	# Part 2: full games, the rule on and off (same seeds). The player builds,
	# explores, and attacks now and then (wars). Measures what ZOC changes.
	var n_games: int = H.games(300)
	for on in [false, true]:
		var st := {"turns": 0, "your outposts lost": 0, "AI outposts lost": 0, "cities taken": 0, "unit fights": 0}
		var ends := {}
		var impossible := 0
		for g in n_games:
			seed(1000 + g)
			m = load("res://main.tscn").instantiate()
			root.add_child(m)
			s = m.state
			s.zoc_on = on
			for step in 4: s.choose(s.Crossing.EVENTS[step]["choices"][(g >> step) & 1]["effects"])
			s.start_landing()
			var spots = H.landing_spots(s)
			s.try_land(spots[(g * 7) % spots.size()])
			while not s.game_over:
				H.answer_choices(s)
				if s.player.outposts.size() < 2 and s.player.industry >= GameState.OUTPOST_COST and not s.outpost_spots(s.player).is_empty(): s.player_build_outpost(s.outpost_spots(s.player).pick_random())
				elif s.gold_change(s.player) >= GameState.ARMY_GOLD: s.player_build_unit()
				for u in s.player.units.duplicate():
					if not u in s.player.units or u.moves <= 0: continue
					var opts = HexMap.neighbours(u.pos).filter(func(c): return s.passable(c) and s.war_target(c) == null and s.can_afford_move(u, c) and not s.is_city(c))
					if g % 2 == 0 and randf() < 0.05:
						opts = HexMap.neighbours(u.pos).filter(func(c): return s.unit_at(c) != null and s.unit_at(c).faction != s.player)
					if not opts.is_empty(): s.player_unit_act(u, opts.pick_random())
				H.answer_choices(s)
				var lords_before = s.factions.map(func(f): return f.overlord)
				s.messages.clear()
				s.end_turn()
				for msg in s.messages:
					if "took your outpost" in msg: st["your outposts lost"] += 1
					elif "took the" in msg and "outpost" in msg: st["AI outposts lost"] += 1
					if " attacked " in msg and "city" not in msg: st["unit fights"] += 1
				for i in s.factions.size():
					if s.factions[i].overlord != "" and s.factions[i].overlord != lords_before[i]: st["cities taken"] += 1
				if s.has_pending_offer(): s.pending_relation().answer(randf() < 0.5)
				for f in s.factions:
					for u in f.units:
						if not s.passable(u.pos) or s.unit_at(u.pos) != u: impossible += 1
				if s.turn > 41: impossible += 1; break
			st["turns"] += s.turn
			ends[s.end_title] = ends.get(s.end_title, 0) + 1
			m.queue_free()
		print("ZOC %s, %d games, per game: %s" % ["ON " if on else "OFF", n_games, ", ".join(st.keys().map(func(k): return "%s %.2f" % [k, st[k] / float(n_games)]))])
		print("   Endings: %s; impossible states %d (expect 0)" % [ends, impossible])
	quit()
