extends SceneTree
const H := preload("res://tests/helpers.gd")
# Where Sköll comes out: distance from the rift he uses to the nearest city
# (and to yours), on arrival and every time he's driven back; that every city
# owns one rift; who he hunts first (fair share 25% each). Checks no rift is
# closer than Rifts.MIN_CITY_DISTANCE.
func _initialize() -> void:
	await process_frame
	seed(61)
	var no_rift := {}; var first_target := {}
	var dist := {}; var yours := {}; var rift_counts := {}; var bad := 0; var outs := 0
	var her_arrivals := 0; var hunts_her := 0 # first arrivals while she is sheltered: does he come for her protector?
	var n_games: int = H.games(300)
	for g in n_games:
		var m = load("res://main.tscn").instantiate()
		root.add_child(m)
		var s = m.state
		for step in 4: s.choose(s.Crossing.EVENTS[step]["choices"][(g >> step) & 1]["effects"])
		s.start_landing()
		var spots = H.landing_spots(s)
		s.try_land(spots[(g * 7) % spots.size()])
		var watched := 0
		var last_pos := HexMap.NO_CELL
		while not s.game_over and watched < 3 and s.turn < 60:
			H.answer_choices(s)
			s.end_turn()
			if s.has_pending_offer(): s.pending_relation().answer(false)
			if s.turn == 3:
				rift_counts[s.rifts.cells.size()] = rift_counts.get(s.rifts.cells.size(), 0) + 1
				for f in s.factions: # every city must own exactly one rift
					if s.rifts.city.values().count(f.name) != 1: no_rift[f.name] = no_rift.get(f.name, 0) + 1
			for r in s.rifts.cells:
				for f in s.factions:
					if f.is_alive() and HexMap.hex_distance(r, f.city_pos) < Rifts.MIN_CITY_DISTANCE: bad += 1
			# a fresh appearance: he's at the rift he last came through
			if s.skoll.active and s.skoll.pos == s.rifts.revealed and s.skoll.pos != last_pos:
				last_pos = s.skoll.pos
				var near := 99
				for f in s.factions:
					if f.is_alive(): near = mini(near, HexMap.hex_distance(s.skoll.pos, f.city_pos))
				dist[near] = dist.get(near, 0) + 1
				if s.player.is_alive():
					var d: int = HexMap.hex_distance(s.skoll.pos, s.player.city_pos)
					yours[d] = yours.get(d, 0) + 1
				if watched == 0 and s.skoll.target != null: first_target[s.skoll.target.name] = first_target.get(s.skoll.target.name, 0) + 1
				if watched == 0 and s.daughter.state == SunDaughter.State.SHELTERED and s.daughter.holder != null:
					her_arrivals += 1
					if s.skoll.target == s.daughter.holder: hunts_her += 1
				outs += 1; watched += 1
		m.queue_free()
	var keys = dist.keys(); keys.sort()
	print("Rifts per map on turn 3: %s; cities without exactly one rift of their own: %s" % [rift_counts, no_rift])
	print("Who he hunts when he first arrives: %s" % first_target)
	print("First arrival hunts her protector's city: %d%% of %d (he scents her: expect about 40%%)" % [roundi(100.0 * hunts_her / maxi(1, her_arrivals)), her_arrivals])
	print("%d appearances; distance to the nearest city: %s" % [outs, ", ".join(keys.map(func(k): return "%d: %d%%" % [k, roundi(100.0 * dist[k] / outs)]))])
	var yk = yours.keys(); yk.sort()
	print("distance to YOUR city: %s" % ", ".join(yk.map(func(k): return "%d: %d%%" % [k, roundi(100.0 * yours[k] / outs)])))
	print("Rifts closer than %d to a city: %d" % [Rifts.MIN_CITY_DISTANCE, bad])
	quit()
