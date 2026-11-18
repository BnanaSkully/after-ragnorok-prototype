extends SceneTree
const H := preload("res://tests/helpers.gd")
func _initialize() -> void:
	await process_frame
	seed(99)
	var bad := {}
	var ends := {}
	var holders := {}
	var stats := {"ai vs ai fights": 0, "offers": 0, "player diplomacy": 0, "ai betrayals": 0, "ai cities fallen": 0, "first attack on you": 0, "first attack on an ai": 0}
	var n_games: int = H.games(300)
	for g in n_games:
		var m = load("res://main.tscn").instantiate()
		root.add_child(m)
		var s = m.state
		for step in 4: s.choose(s.Crossing.EVENTS[step]["choices"][(g >> step) & 1]["effects"])
		s.start_landing()
		holders[s.daughter.holder.name] = holders.get(s.daughter.holder.name, 0) + 1
		var spots = []
		for r in HexMap.ROWS:
			for c in HexMap.COLS:
				if s.can_land_at(Vector2i(c, r)): spots.append(Vector2i(c, r))
		s.try_land(spots[(g * 7) % spots.size()])
		var first := ""
		while not s.game_over:
			H.answer_choices(s)
			if s.player.industry >= 10 and s.player.walls < 1 and s.turn >= 8: s.player_build_walls()
			elif s.player.units.size() < 3: s.player_build_unit()
			if g % 2 == 0:
				var f = s.ais[s.turn % 3]
				if s.relation(f).can_propose():
					s.player_propose_pact(f); stats["player diplomacy"] += 1
			s.end_turn()
			if s.has_pending_offer():
				stats["offers"] += 1
				s.pending_relation().answer(randf() < 0.5)
			for msg in s.messages:
				var ai_names = ["Japanese", "Celtic", "Greek"]
				for a in ai_names:
					for b in ai_names:
						if a != b and msg.begins_with("%s attacked %s" % [a, b]): stats["ai vs ai fights"] += 1
				if "BROKE THEIR" in msg: stats["ai betrayals"] += 1
				if first == "" and msg.begins_with("Sköll attacked") and "city" in msg:
					first = "you" if msg.contains("Norse's city") else "ai"
				if first == "" and msg.contains("city (defence") and msg.contains("held"):
					first = "you" if msg.begins_with("Norse's city") else "ai"
			var seen := {}
			for f in s.factions:
				if f.food < 0: bad["negative food"] = bad.get("negative food", 0) + 1
				if not f.is_alive() and f.units.size() > 0: bad["units of fallen faction"] = 1
				for u in f.units:
					if seen.has(u.pos) or not HexMap.in_bounds(u.pos) or s.skoll.is_at(u.pos): bad["unit position"] = bad.get("unit position", 0) + 1
					seen[u.pos] = true
			if s.daughter.is_rogue() and (s.unit_at(s.daughter.pos) != null or s.is_city(s.daughter.pos)): bad["daughter position"] = 1
			for r in s.relations:
				if r.trust < -10 or r.trust > 10: bad["trust range"] = 1
			if s.turn > 40: bad["game never ended"] = 1; break
		if first != "": stats["first attack on " + ("you" if first == "you" else "an ai")] += 1
		for f in s.ais:
			if not f.is_alive(): stats["ai cities fallen"] += 1
		ends[s.end_title] = ends.get(s.end_title, 0) + 1
		m.queue_free()
	print("Daughter chose at the Landing: %s" % holders)
	print("Endings: %s" % ends)
	print("Stats over 300 games: %s" % stats)
	print("Impossible states: %s" % (bad if bad.size() > 0 else "none"))
	quit()
