extends SceneTree
const H := preload("res://tests/helpers.gd")
const Buildings := preload("res://buildings.gd")
# Production queue: each rule on a set-up game, then games with the same seeds
# played twice, by a player who buys at once and one who only queues, to see
# what the queue changes (it should cost a little time, not change the game).
func new_game():
	var m = load("res://main.tscn").instantiate()
	root.add_child(m)
	var s = m.state
	for step in 4: s.choose(s.Crossing.EVENTS[step]["choices"][0]["effects"])
	H.flatten(s); s.start_landing(); s.try_land(Vector2i(6, 4))
	return m

func next_turn(s) -> void:
	H.answer_choices(s)
	s.end_turn()
	if s.has_pending_offer(): s.pending_relation().answer(false)
	H.answer_choices(s)

func _initialize() -> void:
	await process_frame
	seed(4)
	var m = new_game(); var s = m.state; var p = s.player
	p.industry = 0
	var income: int = s.industry_change(p) - s.tribute_amount(p)
	var units: int = p.units.size()
	s.player_queue("army")
	next_turn(s)
	print("1. army queued, income %d: after one turn production %d (expect %d), store %d (expect 0), units %d (expect %d)" % [income, p.production, income, p.industry, p.units.size(), units])
	var turns := 1
	while p.units.size() == units and turns < 10:
		next_turn(s); turns += 1
	print("   finished after %d turns (expect %d), queue empty=%s, leftover went to the store: store %d, production %d (expect 0)" % [turns, ceili(5.0 / income), p.queue.is_empty(), p.industry, p.production])
	print("   the new army can move at once: moves %d (expect 1)" % p.units[-1].moves)
	# queue limits
	p.industry = 0
	for key in Buildings.LIST: s.player_queue(key)
	s.player_queue("granary")
	print("2. queued every building: %d items (expect %d), granary twice refused=%s" % [p.queue.size(), Buildings.LIST.size(), p.queue.count("granary") == 1])
	s.player_queue("walls")
	print("   a sixth item refused: queue %d (expect %d)" % [p.queue.size(), GameState.QUEUE_MAX])
	# taking items out
	p.production = 4
	s.player_unqueue(0)
	print("3. took one out: production still %d (expect 4), queue %d" % [p.production, p.queue.size()])
	while not p.queue.is_empty(): s.player_unqueue(0)
	print("   took the last out: production %d (expect 0), store %d (expect 4)" % [p.production, p.industry])
	# finish now
	p.industry = 20
	s.player_queue("workshop")
	p.production = 5
	s.player_hurry()
	print("4. Finish now on the Workshop (12, 5 in): store 20 -> %d (expect 13), built=%s, production %d" % [p.industry, p.buildings.has("workshop"), p.production])
	p.industry = 1
	s.player_queue("forge")
	s.player_hurry()
	print("   with 1 Industry the Forge (10) can't be finished: built=%s (expect false), store %d (expect 1)" % [p.buildings.has("forge"), p.industry])
	p.queue.clear(); p.production = 0
	# blocked item: supply full
	while s.army_count(p) < s.supply_cap(p): p.add_unit(s.free_spot_near(p.city_pos))
	p.queue.append("army")
	s.player_queue("watchtower")
	p.industry = 40 # (enough for the upkeep: no army disbands)
	p.food = 40
	var armies: int = s.army_count(p)
	for i in 6: next_turn(s)
	print("5. army waits (supply full), watchtower behind it: watchtower built=%s (expect true), armies %d (expect %d), army still queued=%s" % [p.buildings.has("watchtower"), s.army_count(p), armies, p.queue == ["army"]])
	var before: int = p.industry
	next_turn(s)
	print("   with only a blocked item left, Industry goes to the store: %d -> %d, production %d unchanged" % [before, p.industry, p.production])
	m.queue_free()

	var n_games: int = H.games(300)
	var stats := {}
	var bad := {}
	for mode in ["buy", "queue"]:
		var ends := {}; var armies20 := 0.0; var built20 := 0.0; var stored20 := 0.0
		for g in n_games:
			seed(1000 + g)
			m = load("res://main.tscn").instantiate()
			root.add_child(m)
			s = m.state; p = s.player
			for step in 4: s.choose(s.Crossing.EVENTS[step]["choices"][(g >> step) & 1]["effects"])
			s.start_landing()
			var spots = H.landing_spots(s)
			s.try_land(spots[(g * 7) % spots.size()])
			while not s.game_over:
				H.answer_choices(s)
				var want := "army" if s.gold_change(p) >= GameState.ARMY_GOLD and s.army_count(p) < s.supply_cap(p) else ""
				if want == "":
					for key in Buildings.LIST:
						if not p.buildings.has(key): want = key; break
				if mode == "buy":
					if want == "army": s.player_build_unit()
					elif want != "": s.player_build_building(want)
				elif p.queue.is_empty() and want != "":
					s.player_queue(want)
				var armies_before: int = s.army_count(p)
				s.end_turn()
				if s.has_pending_offer(): s.pending_relation().answer(false)
				# (an event can cost population and leave you over supply: only a NEW army over supply is wrong)
				if s.army_count(p) > armies_before and s.army_count(p) > s.supply_cap(p): bad["army built over supply (%s)" % mode] = 1
				if s.turn == 20:
					armies20 += s.army_count(p) / float(n_games); built20 += p.buildings.size() / float(n_games); stored20 += p.industry / float(n_games)
				if p.production < 0 or p.industry < 0: bad["negative Industry or production"] = 1
				if p.queue.size() > GameState.QUEUE_MAX: bad["queue too long"] = 1
				if s.turn > 60: bad["game never ended"] = 1; break
			ends[s.end_title] = ends.get(s.end_title, 0) + 1
			m.queue_free()
		stats[mode] = "on turn 20: %.1f armies, %.1f buildings, %.1f Industry stored. Endings %s" % [armies20, built20, stored20, ends]
	print("6. %d games, same seeds:" % n_games)
	print("   buy at once: %s" % stats["buy"])
	print("   queue only:  %s" % stats["queue"])
	print("Impossible states: %s" % (bad if bad.size() > 0 else "none"))
	quit()
