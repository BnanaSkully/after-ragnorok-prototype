extends SceneTree
const H := preload("res://tests/helpers.gd")
func new_game():
	var m = load("res://main.tscn").instantiate()
	root.add_child(m)
	var s = m.state
	for step in 4: s.choose(s.Crossing.EVENTS[step]["choices"][0]["effects"])
	H.flatten(s); s.start_landing()
	s.try_land(Vector2i(6, 4))
	s.daughter.join(s.player)
	return m
func _initialize() -> void:
	await process_frame
	var m = new_game(); var s = m.state
	var greek = s.ais[2]
	greek.favour = 5; greek.units.resize(1); s.player.units.resize(1)
	print("1. turn 1: can trade=%s (expect false, only from turn 10)" % s.can_trade_daughter())
	s.turn = 10
	print("   turn 10 (howling), Greek Favour 5, equal armies: value %d (expect 6-3=3)" % s.daughter_value(greek))
	greek.favour = 9
	print("   Greek Favour 9: value %d (expect 7)" % s.daughter_value(greek))
	greek.favour = 5
	s.skoll.active = true; s.skoll.pos = Vector2i(0, 0); s.skoll.target = s.ais[0]
	print("   Sköll loose: value %d (expect 0)" % s.daughter_value(greek))
	s.skoll.target = greek
	print("   Sköll hunting the Greeks: value %d (expect -3)" % s.daughter_value(greek))
	for c in [Vector2i(13, 9), Vector2i(11, 9), Vector2i(13, 7)]: greek.add_unit(c)
	print("   Greek army %d vs yours %d: value %d (expect -3 - 3 = -6)" % [s.army_power(greek), s.army_power(s.player), s.daughter_value(greek)])
	greek.favour = 1
	var q = s.trade_quote(greek)
	print("   Greek Favour 1 too: value %d, refuses=%s (expect -10, true)" % [q["value"], q["refuses"]])
	m.queue_free()
	# 2. a trade where they pay
	m = new_game(); s = m.state
	s.turn = 10; var celtic = s.ais[1]; celtic.favour = 8; celtic.industry = 3; s.player.favour = 7
	var q2 = s.trade_quote(celtic)
	var pi = s.player.industry
	var ok = s.player_trade_daughter(celtic)
	print("2. Celtic value %d but only 3 Industry -> they pay %d; traded=%s, holder %s, your Industry %d -> %d, Celtic Industry %d, her Favour toward you 7 -> %d, action used=%s" % [q2["value"], q2["they_pay"], ok, s.daughter.holder.name, pi, s.player.industry, celtic.industry, s.player.favour, s.diplomacy_action_used])
	print("   message: %s" % [s.messages])
	m.queue_free()
	# 3. a trade where you pay, and can't afford
	m = new_game(); s = m.state
	s.turn = 10; s.skoll.active = true; s.skoll.pos = Vector2i(0, 0); var jp = s.ais[0]; s.skoll.target = jp; jp.favour = 4
	s.player.industry = 2
	var q3 = s.trade_quote(jp)
	print("3. Japanese hunted by Sköll: value %d -> you pay %d; with 2 Industry possible=%s; trade refused=%s" % [q3["value"], q3["you_pay"], q3["possible"], not s.player_trade_daughter(jp)])
	s.player.industry = 10
	print("   with 10 Industry: traded=%s, your Industry now %d, holder %s" % [s.player_trade_daughter(jp), s.player.industry, s.daughter.holder.name])
	m.queue_free()
	# 4. an AI offers her to you
	m = new_game(); s = m.state
	var greek2 = s.ais[2]
	s.daughter.join(greek2); s.turn = 14; s.skoll.active = true; s.skoll.pos = Vector2i(0, 0); s.skoll.target = greek2; greek2.favour = 4; greek2.industry = 6
	var r = s.relation(greek2)
	var got := false
	for i in 50:
		r.rival_make_offer()
		if r.pending.get("type") == "daughter": got = true; break
	print("4. Greek (afraid, value %d) offers her to you: %s, they'd pay %d" % [s.daughter_value(greek2), got, r.pending.get("pay", -1)])
	print("   pop-up: %s" % r.pending_text().split("\n")[0])
	var pind = s.player.industry
	r.answer(true)
	print("   took her: holder %s, your Industry %d -> %d, Greek Favour 4 -> %d, Trust %+d" % [s.daughter.holder.name, pind, s.player.industry, greek2.favour, r.trust])
	m.queue_free()
	# 5. full games with trading
	var bad := 0; var trades := 0; var ai_offers := 0; var ends := {}
	for g in 200:
		m = new_game(); s = m.state
		while not s.game_over:
			H.answer_choices(s)
			if g % 2 == 0 and s.can_trade_daughter():
				var f = s.ais[g % 3]
				if s.trade_quote(f)["possible"] and s.player_trade_daughter(f): trades += 1
			s.end_turn()
			if s.has_pending_offer():
				if s.pending_relation().pending["type"] == "daughter": ai_offers += 1
				s.pending_relation().answer(randf() < 0.5)
			for f in s.factions:
				if f.industry < 0 or f.food < 0 or f.favour < 0 or f.favour > 10: bad += 1
			if s.daughter.state == SunDaughter.State.SHELTERED and s.daughter.holder != null and not s.daughter.holder.is_alive(): bad += 1
		ends[s.end_title] = ends.get(s.end_title, 0) + 1
		m.queue_free()
	print("5. 200 games: %d trades by you, %d AI offers of her, endings %s, impossible states %d" % [trades, ai_offers, ends, bad])
	quit()
