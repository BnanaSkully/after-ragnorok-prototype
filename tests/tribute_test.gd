extends SceneTree
const H := preload("res://tests/helpers.gd")

# Taking cities: they become tributaries. Part 1: each rule on a set-up game.
# Part 2: 300 full games (cities taken, uprisings, impossible states).

func new_game():
	var m = load("res://main.tscn").instantiate()
	root.add_child(m)
	var s = m.state
	for step in 4: s.choose(s.Crossing.EVENTS[step]["choices"][0]["effects"])
	H.flatten(s); s.start_landing(); s.try_land(Vector2i(6, 4))
	return m

func clear_city(s, f) -> void:
	for u in f.units.duplicate():
		if u.pos == f.city_pos: f.remove_unit(u)
	f.walls = 0

func _initialize() -> void:
	await process_frame
	seed(8)
	var m = new_game(); var s = m.state
	var greek = s.ais[2]
	s.relation(greek).player_declare_war()
	clear_city(s, greek); greek.walls = 1
	var u = s.player.units[0]; u.pos = greek.city_pos + Vector2i(-1, 0); u.moves = 1; u.strength = 100
	print("1. Greek city defence %d; your unit attacks it (Strength 100)" % s.city_defence(greek))
	s.player_unit_act(u, greek.city_pos)
	print("   Greek tributary of %s=%s, at war=%s, walls 1 -> %d, your unit still outside=%s" % [greek.overlord, greek.overlord == "Norse", s.at_war(s.player, greek), greek.walls, u.pos != greek.city_pos])
	var gi = s.industry_change(greek)
	var pi0 = s.player.industry; var gi0 = greek.industry
	s.end_turn(); H.answer_choices(s)
	if s.has_pending_offer(): s.pending_relation().answer(false)
	print("2. one turn: Greek income %d, pays you %d; your Industry %d -> %d (own income %d), Greek %d -> %d" % [gi, s.tribute_amount(greek), pi0, s.player.industry, s.industry_change(s.player), gi0, greek.industry])
	var declared := false
	s.relation(greek).trust = -10
	for i in 50:
		s.relation(greek).rival_consider_war()
		if s.relation(greek).at_war: declared = true
	print("3. a tributary that hates you (Trust -10), 50 tries: declared war=%s (expect false: only an uprising)" % declared)
	s.player.units[0].strength = 3
	for i in 4: greek.add_unit(Vector2i(13, 9 - i))
	var tries := 0
	while greek.overlord != "" and tries < 50:
		s.ai_rebellions(); tries += 1
	print("4. Greek army %d vs yours %d: rose up after %d turns; free=%s, at war with you=%s" % [s.army_power(greek), s.army_power(s.player), tries, greek.overlord == "", s.at_war(s.player, greek)])
	m.queue_free()
	# 5. your city taken: you pay tribute, the game goes on, you can rise up
	m = new_game(); s = m.state
	var jp = s.ais[0]
	s.relation(jp).rival_declare_war("test")
	clear_city(s, s.player)
	var ju = jp.units[0]; ju.pos = s.player.city_pos + Vector2i(1, 0); ju.strength = 100
	s.attack_city(ju, s.player)
	print("5. Japanese take your city: you are tributary of %s, game over=%s, at war=%s" % [s.player.overlord, s.game_over, s.at_war(s.player, jp)])
	var mine = s.player.units[0]; mine.pos = ju.pos + Vector2i(1, 0); mine.moves = 1
	print("   attacking a Japanese unit is a war target: %s" % (s.war_target(ju.pos).name if s.war_target(ju.pos) else "none"))
	s.player_unit_act(mine, ju.pos)
	print("   you rose up: free=%s, at war=%s; log: %s" % [s.player.overlord == "", s.at_war(s.player, jp), s.diplomacy_log[-1].left(60)])
	m.queue_free()
	# 6. odds against a city, alone and with support; a lost attack kills the attacker
	var won := [0, 0]; var died := [0, 0]
	for helpers in [0, 2]:
		for i in 200:
			m = new_game(); s = m.state; greek = s.ais[2]
			s.relation(greek).player_declare_war()
			greek.walls = 1 # defence 3 (garrison) + 4 = 7
			s.daughter.join(s.player) # (her +3 would change the Greek defence)
			var spots = HexMap.neighbours(greek.city_pos).filter(func(c): return s.unit_at(c) == null)
			u = s.player.units[0]; u.pos = spots[0]; u.moves = 1
			for k in helpers: s.player.add_unit(spots[k + 1])
			s.player_unit_act(u, greek.city_pos)
			if greek.overlord != "": won[helpers / 2] += 1
			if not u in s.player.units: died[helpers / 2] += 1
			m.queue_free()
	print("6. Strength 3 against defence 7, 200 tries: alone won %d%% (expect 30%%), lost the unit %d%%; with 2 armies beside it (attack 7) won %d%% (expect 50%%)" % [won[0] / 2, died[0] / 2, won[1] / 2])
	# 7. Sköll destroys an overlord: its tributary goes free
	m = new_game(); s = m.state; greek = s.ais[2]; jp = s.ais[0]
	s.make_tributary(greek, jp)
	clear_city(s, jp)
	s.skoll.active = true; s.skoll.strength = 100; s.skoll.pos = jp.city_pos + Vector2i(-1, 0)
	s.skoll.attack_city(jp)
	print("7. Sköll destroys the Japanese city: Greek free=%s" % (greek.overlord == ""))
	m.queue_free()
	# Part 2: 300 games
	var bad := {}; var ends := {}
	var st := {"cities taken": 0, "your city taken": 0, "you took one": 0, "uprisings": 0, "tributary turns (you)": 0}
	for g in 300:
		m = load("res://main.tscn").instantiate()
		root.add_child(m)
		s = m.state
		for step in 4: s.choose(s.Crossing.EVENTS[step]["choices"][(g >> step) & 1]["effects"])
		s.start_landing()
		var spots = H.landing_spots(s)
		s.try_land(spots[(g * 7) % spots.size()])
		while not s.game_over:
			H.answer_choices(s)
			if s.player.industry >= 10 and s.player.walls < 2 and s.turn >= 8: s.player_build_walls()
			elif s.food_change(s.player) > 0: s.player_build_unit()
			if randf() < 0.3: s.player_propose_pact(s.ais[randi() % 3])
			# sometimes attack a city next to one of your units
			if g % 4 == 0:
				for pu in s.player.units.duplicate():
					if not pu in s.player.units or pu.moves <= 0: continue
					for c in HexMap.neighbours(pu.pos):
						var o = s.city_owner(c)
						if o != null and o != s.player and s.win_chance(pu.strength, s.city_defence(o)) >= 0.4:
							s.player_unit_act(pu, c); break
			s.messages.clear()
			s.end_turn()
			if s.has_pending_offer(): s.pending_relation().answer(randf() < 0.5)
			for msg in s.messages + s.diplomacy_log.slice(-3):
				pass
			for msg in s.messages:
				if " took " in msg and "tribute" in msg:
					st["cities taken"] += 1
					if "took your city" in msg: st["your city taken"] += 1
					if msg.contains(": You took"): st["you took one"] += 1
				if "rose up" in msg: st["uprisings"] += 1
			if s.player.overlord != "": st["tributary turns (you)"] += 1
			for f in s.factions:
				if f.overlord == f.name: bad["own overlord"] = 1
				if f.food < 0 or f.industry < 0: bad["negative stores"] = bad.get("negative stores", 0) + 1
				var lord = s.overlord_of(f)
				if lord != null and s.at_war(f, lord): bad["at war with overlord"] = bad.get("at war with overlord", 0) + 1
				if lord != null and lord.overlord == f.name: bad["each other's overlord"] = 1
				if not f.is_alive() and f.overlord != "": bad["fallen faction pays tribute"] = 1
				for u2 in f.units:
					var co = s.city_owner(u2.pos)
					if co != null and co != f: bad["unit inside another city"] = bad.get("unit inside another city", 0) + 1
			if s.turn > 40: bad["game never ended"] = 1; break
		ends[s.end_title] = ends.get(s.end_title, 0) + 1
		m.queue_free()
	print("300 games, per game: %s" % ", ".join(st.keys().map(func(k): return "%s %.2f" % [k, st[k] / 300.0])))
	print("Endings: %s" % ends)
	print("Impossible states: %s" % (bad if bad.size() > 0 else "none"))
	quit()
