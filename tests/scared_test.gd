extends SceneTree
func _initialize() -> void:
	await process_frame
	seed(31)
	var games_ai_held := 0; var games_with_offer := 0; var offers := 0; var free := 0; var paid := 0; var taken := 0; var bad := 0
	for g in 300:
		var m = load("res://main.tscn").instantiate()
		root.add_child(m)
		var s = m.state
		for step in 4: s.choose(s.Crossing.EVENTS[step]["choices"][1]["effects"]) # selfish choices: she'll pick an AI
		s.start_landing()
		var spots = []
		for r in HexMap.ROWS:
			for c in HexMap.COLS:
				if s.can_land_at(Vector2i(c, r)): spots.append(Vector2i(c, r))
		s.try_land(spots[(g * 7) % spots.size()])
		if s.daughter.holder == s.player: m.queue_free(); continue
		games_ai_held += 1
		var got := false
		while not s.game_over:
			if s.player.units.size() < 2: s.player_build_unit()
			s.end_turn()
			if s.has_pending_offer():
				var r = s.pending_relation()
				if r.pending["type"] == "daughter":
					offers += 1; got = true
					if r.pending["pay"] > 0: paid += 1
					else: free += 1
					var accept = g % 2 == 0
					r.answer(accept)
					if accept and s.daughter.holder == s.player: taken += 1
				else:
					r.answer(false)
			for f in s.factions:
				if f.industry < 0: bad += 1
		if got: games_with_offer += 1
		m.queue_free()
	print("Games where an AI got her at the Landing: %d" % games_ai_held)
	print("  ...and later offered her to you: %d (%d%%)" % [games_with_offer, roundi(100.0 * games_with_offer / max(1, games_ai_held))])
	print("Offers in total: %d (they'd pay you: %d, for nothing: %d); you took her %d times; impossible states %d" % [offers, paid, free, taken, bad])
	quit()
