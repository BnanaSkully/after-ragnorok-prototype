extends SceneTree
const H := preload("res://tests/helpers.gd")

# Closed borders. Part 1: each rule on a set-up game. Part 2: 300 games where
# no unit may ever end a turn inside territory it isn't allowed in.

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
	seed(13)
	var m = new_game(); var s = m.state
	var greek = s.ais[2]; var celtic = s.ais[1]; var r = s.relation(greek)
	var inside = greek.city_pos + Vector2i(-1, 0)
	print("1. at peace: you may enter Greek land=%s, they may enter yours=%s (expect false, false)" % [s.may_enter(s.player, inside), s.may_enter(greek, s.player.city_pos + Vector2i(1, 0))])
	print("   Celtic may enter Greek land=%s (expect false: AIs keep borders closed at peace)" % s.may_enter(celtic, inside))
	# 2. a Greek army next to your land never steps in at peace
	var gu = greek.units[0]
	var entered := false
	for i in 40:
		gu.pos = s.player.city_pos + Vector2i(2, 0); gu.moves = 1
		s.ai_take_turn(greek)
		if s.territory_owner(gu.pos) == s.player: entered = true
	print("2. Greek army beside your land, 40 AI turns: stepped in=%s (expect false)" % entered)
	# 3. your unit at the border: the first step in is a war target
	var u = s.player.units[0]; u.pos = inside + Vector2i(-1, 0); u.moves = 1
	for x in greek.units.duplicate():
		if x.pos == inside: greek.remove_unit(x)
	print("3. stepping into Greek land: war target=%s; stepping in -> at war=%s, unit inside=%s" % [s.war_target(inside).name if s.war_target(inside) else "none", (func(): s.player_unit_act(u, inside); return s.at_war(s.player, greek)).call(), u.pos == inside])
	# 4. peace: your unit walks out at the end of the turn
	r.make_peace()
	play_turn(s)
	print("4. peace made: your unit inside Greek land after the turn=%s (expect false); message: %s" % [s.territory_owner(u.pos) == greek, s.messages.filter(func(x): return "borders are closed" in x)])
	m.queue_free()
	# 5. open borders, both ways, and they run out
	m = new_game(); s = m.state; celtic = s.ais[1]; r = s.relation(celtic)
	r.trust = 10
	var agreed = r.ask_open_borders()
	inside = celtic.city_pos + Vector2i(1, 0)
	print("5. open borders agreed=%s (Trust 10 -> %d%%): you may enter=%s, they may enter yours=%s" % [agreed, roundi(r.borders_chance() * 100), s.may_enter(s.player, inside), s.may_enter(celtic, s.player.city_pos + Vector2i(1, 0))])
	u = s.player.units[0]
	for x in celtic.units.duplicate():
		if x.pos == inside: celtic.remove_unit(x)
	u.pos = inside
	for t in Diplomacy.BORDERS_LENGTH: play_turn(s)
	print("   after %d turns: open=%s, your unit still inside=%s (expect false, false)" % [Diplomacy.BORDERS_LENGTH, r.borders_open(), s.territory_owner(u.pos) == celtic])
	m.queue_free()
	# 6. allies and overlords may cross
	m = new_game(); s = m.state; celtic = s.ais[1]; greek = s.ais[2]
	s.relation(celtic).pact_turns_left = 10
	s.make_tributary(greek, s.player)
	print("6. allied with the Celtic: may enter=%s; Greek your tributary: you may enter=%s, they may enter yours=%s (expect true x3)" % [s.may_enter(s.player, celtic.city_pos + Vector2i(1, 0)), s.may_enter(s.player, greek.city_pos + Vector2i(-1, 0)), s.may_enter(greek, s.player.city_pos + Vector2i(1, 0))])
	m.queue_free()
	# Part 2
	var bad := {}; var st := {"borders agreed": 0, "ai borders offers": 0, "ejected": 0}; var ends := {}
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
			if s.food_change(s.player) > 0: s.player_build_unit()
			var f = s.ais[randi() % 3]
			if randf() < 0.4 and s.relation(f).can_ask_borders():
				if s.relation(f).ask_open_borders(): st["borders agreed"] += 1
			elif randf() < 0.3: s.player_propose_pact(f)
			# wander your units, only where you may go
			for pu in s.player.units.duplicate():
				if not pu in s.player.units or pu.moves <= 0: continue
				var opts = HexMap.neighbours(pu.pos).filter(func(c): return s.passable(c) and s.unit_at(c) == null and not s.is_city(c) and s.war_target(c) == null and s.can_afford_move(pu, c))
				if not opts.is_empty(): s.player_unit_act(pu, opts.pick_random())
			H.answer_choices(s) # (ruins found while moving open a pop-up, which would stop the turn ending)
			s.messages.clear()
			s.end_turn()
			# (checked right after End Turn: units are walked out at the end of the turn)
			for f2 in s.factions:
				for u2 in f2.units:
					if not s.may_enter(f2, u2.pos): bad["unit inside closed borders"] = bad.get("unit inside closed borders", 0) + 1
					if not s.passable(u2.pos): bad["unit on mountain or water"] = 1
			for msg in s.messages:
				if "borders are closed" in msg: st["ejected"] += 1
			if s.has_pending_offer():
				if s.pending_relation().pending["type"] == "borders": st["ai borders offers"] += 1
				s.pending_relation().answer(randf() < 0.5)
			if s.turn > 40: bad["game never ended"] = 1; break
		ends[s.end_title] = ends.get(s.end_title, 0) + 1
		m.queue_free()
	print("300 games, per game: %s" % ", ".join(st.keys().map(func(k): return "%s %.2f" % [k, st[k] / 300.0])))
	print("Endings: %s" % ends)
	print("Impossible states: %s" % (bad if bad.size() > 0 else "none"))
	quit()
