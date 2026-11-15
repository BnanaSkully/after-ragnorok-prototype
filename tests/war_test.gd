extends SceneTree
const H := preload("res://tests/helpers.gd")

# War and peace, and oaths as defensive alliances.
# Part 1: each rule checked on a set-up game. Part 2: 300 full games.

func new_game():
	var m = load("res://main.tscn").instantiate()
	root.add_child(m)
	var s = m.state
	for step in 4: s.choose(s.Crossing.EVENTS[step]["choices"][0]["effects"])
	H.flatten(s); s.start_landing()
	s.try_land(Vector2i(6, 4))
	return m

func _initialize() -> void:
	await process_frame
	seed(77)
	var m = new_game(); var s = m.state
	var jp = s.ais[0]; var celtic = s.ais[1]; var greek = s.ais[2]
	var all_peace := true
	for a in s.factions:
		for b in s.factions:
			if s.at_war(a, b): all_peace = false
	print("1. everyone starts at peace: %s" % all_peace)
	# 2. an AI army next to your unit at peace doesn't attack
	var yours = s.player.units[0]; yours.pos = Vector2i(9, 4)
	var theirs = jp.units[0]; theirs.pos = Vector2i(10, 4)
	for u in jp.units.slice(1): jp.remove_unit(u)
	var attacked := false
	for i in 20:
		theirs.pos = Vector2i(10, 4); theirs.moves = 1
		s.messages.clear(); s.ai_take_turn(jp)
		if s.messages.any(func(x): return x.begins_with("Japanese attacked")): attacked = true
	print("2. Japanese army next to yours at peace, 20 tries: attacked=%s (expect false)" % attacked)
	# 3. you attack them: war, Trust -3, everyone else -1
	theirs.pos = Vector2i(10, 4); yours.moves = 1
	var t_before = [s.relation(jp).trust, s.relation(celtic).trust]
	print("3. war target before attacking: %s" % (s.war_target(Vector2i(10, 4)).name if s.war_target(Vector2i(10, 4)) else "none"))
	s.player_unit_act(yours, Vector2i(10, 4))
	print("   after attacking: at war with Japanese=%s, Japanese Trust %d -> %d, Celtic Trust %d -> %d (warmonger)" % [s.at_war(s.player, jp), t_before[0], s.relation(jp).trust, t_before[1], s.relation(celtic).trust])
	m.queue_free()
	# 4. outposts at peace are safe; at war they can be taken
	m = new_game(); s = m.state; jp = s.ais[0]
	s.player.outposts.append(Vector2i(9, 2))
	var walker = jp.units[0]
	s.enter_hex(walker, Vector2i(9, 2))
	print("4. Japanese unit walks onto your outpost at peace: still yours=%s" % (Vector2i(9, 2) in s.player.outposts))
	s.relation(jp).rival_declare_war("test")
	walker.pos = Vector2i(10, 2)
	s.enter_hex(walker, Vector2i(9, 2))
	print("   at war: taken by the Japanese=%s" % (Vector2i(9, 2) in jp.outposts))
	m.queue_free()
	# 5. your ally joins when you're attacked
	m = new_game(); s = m.state; jp = s.ais[0]; celtic = s.ais[1]; greek = s.ais[2]
	s.relation(celtic).pact_turns_left = 10
	s.relation(greek).rival_declare_war("test")
	print("5. allied with the Celtic, the Greek declare war on you: Celtic at war with Greek=%s (equal armies)" % s.at_war(celtic, greek))
	print("   log: %s" % s.diplomacy_log[-1])
	m.queue_free()
	m = new_game(); s = m.state; jp = s.ais[0]; celtic = s.ais[1]; greek = s.ais[2]
	s.relation(celtic).pact_turns_left = 10
	for i in 3: greek.add_unit(Vector2i(13, 9 - i))
	s.relation(greek).rival_declare_war("test")
	print("   ...but if the Greek army is %d stronger: Celtic joins=%s, Celtic still allied=%s, they broke %d" % [s.army_power(greek) - s.army_power(celtic), s.at_war(celtic, greek), s.relation(celtic).pact_active(), s.relation(celtic).rival_broken_oaths])
	m.queue_free()
	# 6. your ally is attacked: you choose
	for answer in [0, 1]:
		m = new_game(); s = m.state; jp = s.ais[0]; celtic = s.ais[1]
		s.relation(celtic).pact_turns_left = 10
		var fav = s.player.favour
		s.ai_declare_war(jp, celtic)
		var title = s.pending_choices[0]["title"] if s.has_pending_choice() else "none"
		s.answer_choice(answer)
		print("6. Japanese declare war on your Celtic allies: pop-up '%s'; you %s -> at war with Japanese=%s, still allied=%s, Celtic Trust %+d, oathbreaker=%s, her Favour %d -> %d" % [title, "join" if answer == 0 else "stay out", s.at_war(s.player, jp), s.relation(celtic).pact_active(), s.relation(celtic).trust, s.relation(celtic).is_oathbreaker(), fav, s.player.favour])
		m.queue_free()
	# 7. peace brings a truce: no new war from them during it
	m = new_game(); s = m.state; greek = s.ais[2]
	var r = s.relation(greek)
	r.rival_declare_war("test"); r.make_peace(); r.trust = -10
	var declared := false
	for i in 50:
		r.rival_consider_war()
		if r.at_war: declared = true; break
	print("7. after peace (truce until turn %d), Greek Trust -10, 50 tries on turn %d: declared war=%s (expect false)" % [r.truce_until, s.turn, declared])
	s.turn = r.truce_until
	for i in 100:
		r.rival_consider_war()
		if r.at_war: declared = true; break
	print("   after the truce: declared war=%s (expect true)" % declared)
	m.queue_free()
	# 8. attacking your own ally breaks the oath and declares war
	m = new_game(); s = m.state; celtic = s.ais[1]
	s.relation(celtic).pact_turns_left = 10
	var cu = celtic.units[0]; cu.pos = Vector2i(7, 4)
	var pu = s.player.units[0]; pu.pos = Vector2i(6, 4); pu.moves = 1
	var fav2 = s.player.favour
	s.player_unit_act(pu, Vector2i(7, 4))
	print("8. you attack your Celtic allies: at war=%s, allied=%s, Trust %d, oathbreaker=%s, her Favour %d -> %d" % [s.at_war(s.player, celtic), s.relation(celtic).pact_active(), s.relation(celtic).trust, s.relation(celtic).is_oathbreaker(), fav2, s.player.favour])
	m.queue_free()

	# Part 2: 300 full games. The player builds, explores a little, and uses
	# diplomacy at random: proposes oaths, asks for peace, answers every pop-up.
	var st := {"wars on you": 0, "your wars": 0, "ai-ai wars": 0, "peace made": 0, "allies honoured": 0, "allies broke": 0, "calls to arms": 0, "ai betrayals": 0}
	var bad := {}
	var ends := {}
	for g in 300:
		m = load("res://main.tscn").instantiate()
		root.add_child(m)
		s = m.state
		for step in 4: s.choose(s.Crossing.EVENTS[step]["choices"][(g >> step) & 1]["effects"])
		s.start_landing()
		var spots = H.landing_spots(s)
		s.try_land(spots[(g * 7) % spots.size()])
		while not s.game_over:
			while s.has_pending_choice():
				if s.pending_choices[0]["title"] == "YOUR ALLY IS ATTACKED": st["calls to arms"] += 1
				H.answer_choices(s)
			if s.player.industry >= 10 and s.player.walls < 2 and s.turn >= 8: s.player_build_walls()
			elif s.player.outposts.size() < 2 and s.player.industry >= GameState.OUTPOST_COST and not s.outpost_spots(s.player).is_empty(): s.player_build_outpost(s.outpost_spots(s.player).pick_random())
			elif s.food_change(s.player) > 0: s.player_build_unit()
			var f = s.ais[randi() % 3]
			if randf() < 0.5: s.player_propose_pact(f)
			# now and then, attack an AI unit next to one of yours (declaring war)
			if g % 3 == 0 and randf() < 0.15:
				for u in s.player.units.duplicate():
					if not u in s.player.units or u.moves <= 0: continue
					for c in HexMap.neighbours(u.pos):
						var o = s.unit_at(c)
						if o and o.faction != s.player:
							if s.war_target(c) != null: st["your wars"] += 1
							s.player_unit_act(u, c); break
			s.messages.clear()
			s.end_turn()
			for msg in s.messages:
				for a in s.factions:
					for b in s.factions:
						if a != b and msg.begins_with("%s attacked %s" % [a.name, b.name]) and not s.at_war(a, b) and not s.tribute_bound(a, b): bad["fight at peace"] = bad.get("fight at peace", 0) + 1
				if " declared war on the " in msg and msg.begins_with("The "): st["ai-ai wars"] += 1
				if "DECLARED WAR on you" in msg: st["wars on you"] += 1
				if "honour their" in msg: st["allies honoured"] += 1
				if "too afraid of the" in msg: st["allies broke"] += 1
				if "BROKE THEIR" in msg: st["ai betrayals"] += 1
				if "made peace" in msg or "accepted" in msg and "peace" in msg: st["peace made"] += 1
			if s.has_pending_offer():
				var accept = randf() < 0.5
				if s.pending_relation().pending["type"] == "peace" and accept: st["peace made"] += 1
				s.pending_relation().answer(accept)
			for f2 in s.factions:
				if f2.food < 0 or f2.industry < 0: bad["negative stores"] = 1
				for o in f2.outposts:
					if s.outpost_owner(o) != f2: bad["outpost two owners"] = 1
			for rr in s.relations:
				if rr.at_war and rr.pact_active(): bad["at war with an ally"] = 1
				if rr.trust < -10 or rr.trust > 10: bad["trust range"] = 1
			if s.turn > 40: bad["game never ended"] = 1; break
		ends[s.end_title] = ends.get(s.end_title, 0) + 1
		m.queue_free()
	print("300 games, per game: %s" % ", ".join(st.keys().map(func(k): return "%s %.2f" % [k, st[k] / 300.0])))
	print("Endings: %s" % ends)
	print("Impossible states: %s" % (bad if bad.size() > 0 else "none"))
	quit()
