extends SceneTree
const H := preload("res://tests/helpers.gd")

# Refactor check: plays seeded games and prints one line per turn (Sköll, rifts,
# known rifts, ash, every faction's numbers). Run before and after a refactor;
# the output must be identical.
func _initialize() -> void:
	await process_frame
	for g in H.games(12):
		seed(1000 + g)
		var m = load("res://main.tscn").instantiate()
		root.add_child(m)
		var s = m.state
		for step in 4: s.choose(s.Crossing.EVENTS[step]["choices"][g % 2]["effects"])
		s.start_landing()
		var spots = H.landing_spots(s)
		s.try_land(spots[(g * 7) % spots.size()])
		while not s.game_over and s.turn < 41:
			H.answer_choices(s)
			# move a unit or two so ruins, outposts and rifts get found
			for u in s.player.units:
				var opts = HexMap.neighbours(u.pos).filter(func(c): return s.passable(c) and not s.is_blocked(c) and not s.is_city(c))
				if not opts.is_empty() and u.moves > 0 and randf() < 0.7:
					s.player_unit_act(u, opts[randi() % opts.size()])
			H.answer_choices(s)
			if s.player.industry >= GameState.OUTPOST_COST:
				var o = s.outpost_spots(s.player)
				if not o.is_empty(): s.build_outpost(s.player, o[0])
			H.answer_choices(s)
			s.end_turn()
			if s.has_pending_offer(): s.pending_relation().answer(randf() < 0.5)
			var rc = s.rifts.cells
			var rv = s.rifts.revealed
			var line := "g%d t%d sk=%s,%s,%d,%d rifts=%s rev=%s ash=%d" % [g, s.turn, s.skoll.active, s.skoll.pos, s.skoll.strength, s.skoll.wounds, rc, rv, s.ash.size()]
			for f in s.factions:
				line += " | %s %s f%d i%d u%d o%d k%s hp%d" % [f.name, f.city_pos, f.food, f.industry, f.units.size(), f.outposts.size(), f.known_rifts.keys(), f.city_hp]
			print(line)
		print("g%d end: %s / %s" % [g, s.end_title, s.turn])
		m.queue_free()
	quit()
