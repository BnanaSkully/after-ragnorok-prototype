extends SceneTree
const H := preload("res://tests/helpers.gd")
const TurnEvents := preload("res://turn_events.gd")

# The middle and late game: Sköll's cycles, wounds, ash, Sunna's requests and
# rising, and the endings. Part 1: each rule on a set-up game. Part 2: full
# 40-turn games (endings and impossible states).

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

func _initialize() -> void:
	await process_frame
	seed(40)
	var m = new_game(); var s = m.state; var sk = s.skoll
	while s.turn < Skoll.ARRIVAL_TURN: play_turn(s)
	print("1. turn %d: Sköll active=%s, Strength %d, ash hexes %d (expect %d)" % [s.turn, sk.active, sk.strength, s.ash.size(), GameState.ASH_PER_CYCLE])
	var rifts_before = sk.rifts.duplicate()
	sk.drive_back()
	print("   driven back on turn %d: active=%s, returns on turn %d, rifts rolled again=%s" % [s.turn, sk.active, sk.away_until, sk.rifts != rifts_before])
	var back_turn := -1
	for i in 5:
		play_turn(s)
		if sk.active and back_turn < 0: back_turn = s.turn
	print("   back on turn %d (expect %d) with Strength %d (expect %d), ash now %d (expect %d)" % [back_turn, sk.away_until, sk.strength, Skoll.STRENGTH + Skoll.STRENGTH_PER_RETURN, s.ash.size(), 2 * GameState.ASH_PER_CYCLE])
	var bad_ash := 0
	for c in s.ash:
		if s.next_to_a_city(c): bad_ash += 1
	print("   ash next to a city: %d (expect 0)" % bad_ash)
	# 2. immortal: the attacker dies, he's wounded; enough wounds drive him back
	H.answer_choices(s) # (a waiting pop-up blocks every action)
	if s.has_pending_offer(): s.pending_relation().answer(false)
	sk.active = true; sk.wounds = 0; sk.pos = Vector2i(9, 7)
	var u = s.player.add_unit(Vector2i(8, 7)); u.moves = 1
	var st0 = sk.strength
	s.player_unit_act(u, sk.pos)
	print("2. a Strength 3 unit attacks him (Strength %d, Sunna hidden): unit died=%s, wounds %d, Strength now %d" % [st0, not u in s.player.units, sk.wounds, sk.effective_strength()])
	sk.take_turn()
	print("   one turn later his wounds are %d (heal %d a turn)" % [sk.wounds, Skoll.WOUND_HEAL])
	sk.active = true; sk.pos = Vector2i(9, 7); sk.wounds = 0
	var killers := 0
	while sk.active and killers < 10:
		var x = s.player.add_unit(Vector2i(8, 7)); x.moves = 1; x.strength = 4
		s.player_unit_act(x, sk.pos); killers += 1
	print("   Strength 4 attacks until he flees: %d attacks (half his %d is %d), driven back=%s" % [killers, sk.strength, sk.strength / 2, not sk.active])
	m.queue_free()
	# 3. he finds her city, then hunts whoever shelters her
	m = new_game(); s = m.state; sk = s.skoll
	var greek = s.ais[2]; var celtic = s.ais[1]
	s.daughter.join(greek)
	sk.active = true; sk.pos = greek.city_pos + Vector2i(-1, 0); sk.strength = 1
	sk.attack_city(greek)
	print("3. he attacks the Greek city sheltering her and loses: knows her=%s, driven back=%s" % [sk.knows_her, not sk.active])
	s.daughter.join(celtic)
	s.turn = Skoll.ARRIVAL_TURN + 1; sk.away_until = s.turn; sk.take_turn()
	print("   she moves to the Celtic: when he returns he hunts %s (expect the Celtic)" % sk.target_text())
	m.queue_free()
	# 4. swallowed: much stronger but mortal; a combined force kills him
	m = new_game(); s = m.state; sk = s.skoll
	sk.active = true; sk.pos = Vector2i(9, 7)
	sk.swallow_daughter()
	print("4. swallowed: Strength %d (expect %d), mortal=%s" % [sk.strength, Skoll.STRENGTH + Skoll.SWALLOW_BONUS, sk.is_mortal()])
	var helpers = HexMap.neighbours(sk.pos).filter(func(c): return s.unit_at(c) == null)
	var main_u = s.player.add_unit(helpers[0])
	for k in range(1, 4): s.player.add_unit(helpers[k])
	print("   a Strength 3 unit with 3 armies beside him attacks with %d (expect %d)" % [s.wolf_attack(main_u), 3 + 3 * GameState.WOLF_SUPPORT])
	sk.strength = 1
	main_u.moves = 1; s.player_unit_act(main_u, sk.pos)
	print("   against Strength 1: slain=%s, ending '%s'" % [sk.slain, s.end_title])
	m.queue_free()
	# 5. Sunna's requests and her rising
	m = new_game(); s = m.state; sk = s.skoll
	s.daughter.join(s.player); s.player.favour = 7; s.player.food = 50; s.player.industry = 50
	var asked := []
	while s.turn < 19:
		for c in s.pending_choices:
			if c["title"].begins_with("SUNNA"): asked.append(s.turn)
		var fav_before = s.player.favour
		var was_request = s.has_pending_choice() and s.pending_choices[0]["title"].begins_with("SUNNA")
		if was_request:
			var refuse := asked.size() == 1 # refuse the first, grant the rest (refusing twice would drive her out)
			if not refuse and not s.can_afford(s.pending_choices[0]["options"][0]["effects"]):
				refuse = true # (can't grant it, e.g. a guard with no army left: the option is greyed out)
			s.answer_choice(1 if refuse else 0)
			var expect = clampi(fav_before + (SunDaughter.REQUEST_REFUSED if refuse else SunDaughter.REQUEST_GRANTED), 0, SunDaughter.MAX_FAVOUR)
			if s.player.favour != expect: print("   BAD: answering the request changed her Favour %d -> %d, expected %d" % [fav_before, s.player.favour, expect])
		H.answer_choices(s)
		s.end_turn()
		if s.has_pending_offer(): s.pending_relation().answer(false)
		s.daughter.join(s.player) # (keep her even if she'd walk out)
	print("5. Sunna asked on turns %s (expect every %d from %d)" % [asked, SunDaughter.REQUEST_GAP, SunDaughter.REQUEST_FROM])
	s.player.favour = SunDaughter.RISE_FAVOUR; sk.strength = 20; s.skoll.active = true
	var ash_before = s.ash.size()
	while s.turn < GameState.RISE_TURN + 1 and not s.daughter.is_risen(): play_turn(s)
	print("   turn %d, her Favour %d: risen=%s with you=%s; Sköll mortal=%s, Strength %d (expect 20: he keeps it, enraged), knows her=%s" % [s.turn, s.player.favour, s.daughter.is_risen(), s.daughter.risen_with(s.player), sk.is_mortal(), sk.strength, sk.knows_her])
	var parts = s.food_parts(s.player).filter(func(p): return "risen" in p[0])
	s.spread_ash(Vector2i(0, 0))
	print("   her gift: %s; ash spreads after she rose: %s (expect false)" % [parts, s.ash.size() != ash_before])
	m.queue_free()
	# 6. endings: Sköll devours 2 of 4 peoples; Dominion; Dawn
	m = new_game(); s = m.state
	s.devour(s.ais[0]); var after_one = s.game_over
	s.devour(s.ais[1])
	print("6. devoured 1 people: over=%s; 2 of 4: '%s'" % [after_one, s.end_title])
	m.queue_free()
	m = new_game(); s = m.state
	s.turn = GameState.END_TURN; s.final_ending()
	print("   turn %d, nobody risen: '%s' (%s)" % [GameState.END_TURN, s.end_title, s.end_detail.split("\n")[1]])
	m.queue_free()
	m = new_game(); s = m.state
	s.daughter.join(s.player); s.daughter.state = SunDaughter.State.RISEN
	s.turn = GameState.END_TURN; s.final_ending()
	print("   Sunna risen with you at the end: '%s'" % s.end_title)
	m.queue_free()

	# Part 2: full games
	var n_games: int = H.games(300)
	var ends := {}; var bad := {}
	var st := {"returns": 0.0, "ash": 0.0, "rose": 0.0, "rose with you": 0.0, "swallowed": 0.0, "requests": 0.0, "game length": 0.0, "factions devoured": 0.0, "you hold her on turn 10": 0.0, "AIs demand her": 0.0, "wars on you over her": 0.0, "AI wars over her": 0.0, "carried off by a conquest": 0.0}
	for g in n_games:
		m = load("res://main.tscn").instantiate()
		root.add_child(m)
		s = m.state
		for step in 4: s.choose(s.Crossing.EVENTS[step]["choices"][(g >> step) & 1]["effects"])
		s.start_landing()
		var spots = H.landing_spots(s)
		s.try_land(spots[(g * 7) % spots.size()])
		var requests := 0
		while not s.game_over:
			for c in s.pending_choices:
				if c["title"].begins_with("SUNNA"): requests += 1
			H.answer_choices(s)
			if s.player.walls < 2 and s.player.industry >= GameState.WALL_COST and s.turn >= 8: s.player_build_walls()
			elif s.food_change(s.player) > 0: s.player_build_unit()
			for key in GameState.Buildings.LIST: s.player_build_building(key)
			s.end_turn()
			if s.turn == 10 and s.daughter.shelters_with(s.player): st["you hold her on turn 10"] += 1
			for msg in s.messages:
				if "their lost sun)" in msg: st["wars on you over her" if "on you" in msg else "AI wars over her"] += 1
				if "carried" in msg and "off from" in msg: st["carried off by a conquest"] += 1
			if s.has_pending_offer():
				if s.pending_relation().pending.get("type") == "claim": st["AIs demand her"] += 1
				s.pending_relation().answer(randf() < 0.5)
			for c in s.ash:
				if s.next_to_a_city(c): bad["ash next to a city"] = 1
				if s.outpost_owner(c) != null: bad["outpost on ash"] = 1
			if s.skoll.active and not HexMap.in_bounds(s.skoll.pos): bad["Sköll active off the map"] = 1
			if s.turn > GameState.END_TURN: bad["game ran past the end"] = 1; break
		ends[s.end_title] = ends.get(s.end_title, 0) + 1
		st["returns"] += s.skoll.returns; st["ash"] += s.ash.size(); st["game length"] += s.turn
		st["rose"] += int(s.daughter.is_risen()); st["rose with you"] += int(s.daughter.risen_with(s.player))
		st["swallowed"] += int(s.daughter.is_swallowed()); st["requests"] += requests; st["factions devoured"] += s.devoured.size()
		m.queue_free()
	print("Part 2, %d games, per game: %s" % [n_games, ", ".join(st.keys().map(func(k): return "%s %.2f" % [k, st[k] / n_games]))])
	print("Endings: %s" % ends)
	print("Impossible states: %s" % (bad if bad.size() > 0 else "none"))
	quit()
