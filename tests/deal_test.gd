extends SceneTree
const H := preload("res://tests/helpers.gd")

# Trading: quotes, trades, gifts, paying for peace, AI trade offers.
# Part 1: each rule on a set-up game. Part 2: 300 games with random deals.

func new_game():
	var m = load("res://main.tscn").instantiate()
	root.add_child(m)
	var s = m.state
	for step in 4: s.choose(s.Crossing.EVENTS[step]["choices"][0]["effects"])
	H.flatten(s); s.start_landing(); s.try_land(Vector2i(6, 4))
	return m

func _initialize() -> void:
	await process_frame
	seed(21)
	var m = new_game(); var s = m.state
	var celtic = s.ais[1]; var r = s.relation(celtic)
	celtic.food = 10; celtic.industry = 10; s.player.food = 10; s.player.industry = 10
	print("1. Celtic with plenty of both, Trust 0: 5 Food buys %d Industry, 5 Industry buys %d Food (expect 4, 4)" % [r.trade_quote("food"), r.trade_quote("industry")])
	celtic.food = 2
	print("   Celtic short of Food: 5 Food buys %d Industry (expect 5)" % r.trade_quote("food"))
	r.trust = 4
	print("   ...and Trust 4: %d (expect 6)" % r.trade_quote("food"))
	var before = [s.player.food, s.player.industry, celtic.food, celtic.industry]
	var ok = r.trade("food")
	print("2. trade 5 Food: done=%s; you Food %d->%d Industry %d->%d; Celtic Food %d->%d Industry %d->%d; action used=%s" % [ok, before[0], s.player.food, before[1], s.player.industry, before[2], celtic.food, before[3], celtic.industry, s.diplomacy_action_used])
	print("   a second deal the same turn: %s (expect false)" % r.trade("industry"))
	s.diplomacy_action_used = false
	celtic.industry = 0
	print("3. Celtic with no Industry: quote %d (expect 0, no deal)" % r.trade_quote("food"))
	m.queue_free()
	# 4. gifts raise Trust up to the cap
	m = new_game(); s = m.state; celtic = s.ais[1]; r = s.relation(celtic)
	s.player.food = 100
	var trusts := []
	for i in 7:
		s.diplomacy_action_used = false
		r.gift("food"); trusts.append(r.trust)
	print("4. seven gifts of Food: Trust after each %s (expect up to 5, then no more)" % [trusts])
	m.queue_free()
	# 5. paying for peace
	m = new_game(); s = m.state; var greek = s.ais[2]; r = s.relation(greek)
	r.rival_declare_war("test")
	print("5. at war: trade quote %d (expect 0), gift allowed=%s (expect false)" % [r.trade_quote("food"), r.can_gift("food")])
	s.player.industry = 20
	print("   peace chance %d%%, with %d Industry %d%%" % [roundi(r.peace_chance() * 100), Diplomacy.PEACE_TRIBUTE, roundi(r.tribute_peace_chance() * 100)])
	var tries := 0
	while r.at_war and tries < 20:
		s.diplomacy_action_used = false
		var ind = s.player.industry
		var made = r.offer_tribute_for_peace()
		tries += 1
		if not made and s.player.industry != ind: print("   BAD: paid although refused")
	print("   peace after %d offers; Industry left %d (paid %d once); truce=%s" % [tries, s.player.industry, Diplomacy.PEACE_TRIBUTE, r.in_truce()])
	m.queue_free()
	# 6. an AI offers a trade
	m = new_game(); s = m.state; var jp = s.ais[0]; r = s.relation(jp)
	jp.food = 0; jp.industry = 20; s.player.food = 10; s.player.industry = 0
	var got := false
	for i in 200:
		r.rival_make_offer()
		if r.pending.get("type") == "trade": got = true; break
	print("6. Japanese starving with 20 Industry offer a trade: %s; pop-up: %s" % [got, r.pending_text().split("\n")[0] if got else "-"])
	if got:
		var pf = s.player.food; var pi = s.player.industry
		r.answer(true)
		print("   accepted: your Food %d -> %d, Industry %d -> %d" % [pf, s.player.food, pi, s.player.industry])
	m.queue_free()
	# Part 2
	var bad := {}; var st := {"trades": 0, "gifts": 0, "paid peace": 0, "ai trade offers": 0, "accepted ai trades": 0}; var ends := {}
	var n_games: int = H.games(300)
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
			if s.player.industry >= 10 and s.player.walls < 2 and s.turn >= 8: s.player_build_walls()
			elif s.food_change(s.player) > 0: s.player_build_unit()
			var f = s.ais[randi() % 3]; var rr = s.relation(f)
			var pick := randi() % 4
			if pick == 0 and rr.trade_quote("food") > 0 and s.player.food >= 5:
				s.player_trade(f, "food"); st["trades"] += 1
			elif pick == 1 and rr.trade_quote("industry") > 0 and s.player.industry >= 5:
				s.player_trade(f, "industry"); st["trades"] += 1
			elif pick == 2 and rr.can_gift("food"):
				s.player_gift(f, "food"); st["gifts"] += 1
			elif pick == 3 and rr.can_offer_tribute():
				if s.player_tribute_for_peace(f) == null and not rr.at_war: st["paid peace"] += 1
			s.end_turn()
			if s.has_pending_offer():
				var p = s.pending_relation()
				if p.pending["type"] == "trade": st["ai trade offers"] += 1
				var acc = randf() < 0.5
				if acc and p.pending["type"] == "trade": st["accepted ai trades"] += 1
				p.answer(acc)
			for f2 in s.factions:
				if f2.food < 0 or f2.industry < 0: bad["negative stores"] = bad.get("negative stores", 0) + 1
			for x in s.relations:
				if x.trust < -10 or x.trust > 10: bad["trust range"] = 1
			if s.turn > 40: bad["game never ended"] = 1; break
		ends[s.end_title] = ends.get(s.end_title, 0) + 1
		m.queue_free()
	print("300 games, per game: %s" % ", ".join(st.keys().map(func(k): return "%s %.2f" % [k, st[k] / float(n_games)])))
	print("Endings: %s" % ends)
	print("Impossible states: %s" % (bad if bad.size() > 0 else "none"))
	quit()
