extends SceneTree
const H := preload("res://tests/helpers.gd")

# 300 full games where the player actually plays the early game: the scout
# explores (and searches ruins), the city builds a mix of scouts, outposts,
# armies and walls, spare armies guard outposts, and every pop-up is answered.
# Checks impossible states every turn, and counts the decisions the player had
# on turns 1-10: a pop-up (ruin, event, AI offer), something affordable to
# build, or a scout with land left to explore.

func explore_goal(s, u) -> Vector2i:
	var best := HexMap.NO_CELL
	var best_d := 999
	for r in s.ruins:
		if not r["taken"] and s.player.explored.has(r["cell"]) and not s.is_blocked(r["cell"]):
			var d := HexMap.hex_distance(u.pos, r["cell"])
			if d < best_d:
				best_d = d; best = r["cell"]
	return best if best != HexMap.NO_CELL else s.nearest_unexplored(s.player, u.pos)

func _initialize() -> void:
	await process_frame
	seed(2026)
	var bad := {}
	var ends := {}
	var dead_turns := 0; var early_turns := 0
	var kinds := {"pop-up": 0, "build": 0, "scout": 0}
	var stats := {"events": 0, "ruins: you": 0, "ruins: ai": 0, "outposts: you": 0, "outposts: ai": 0, "your outposts taken": 0, "you took one": 0, "rifts found before turn 14": 0, "turn-1 builds possible": 0, "ai betrayals": 0, "ai vs ai fights": 0}
	var explored_by_10 := 0
	var n_games: int = H.games(300)
	for g in n_games:
		var m = load("res://main.tscn").instantiate()
		root.add_child(m)
		var s = m.state
		for step in 4: s.choose(s.Crossing.EVENTS[step]["choices"][(g >> step) & 1]["effects"])
		s.start_landing()
		var spots = H.landing_spots(s)
		s.try_land(spots[(g * 7) % spots.size()])
		if s.player.industry >= GameState.SCOUT_COST: stats["turn-1 builds possible"] += 1
		var last_explored := 0
		while not s.game_over:
			var popups: int = H.answer_choices(s)
			# --- the decisions on offer this turn (before acting)
			var p = s.player
			var can_build: bool = p.industry >= GameState.UNIT_COST or s.can_build_scout(p) or (p.industry >= GameState.OUTPOST_COST and not s.outpost_spots(p).is_empty()) or (p.industry >= GameState.WALL_COST and p.walls < GameState.MAX_WALLS)
			var scouting := false
			for u in p.units:
				if u.is_scout() and s.nearest_unexplored(p, u.pos) != HexMap.NO_CELL: scouting = true
			if s.turn <= 10:
				early_turns += 1
				if popups > 0: kinds["pop-up"] += 1
				if can_build: kinds["build"] += 1
				if scouting: kinds["scout"] += 1
				if popups == 0 and not can_build and not scouting: dead_turns += 1
			# --- build something (a different order each game, to try every option)
			var order := ["outpost", "scout", "army", "walls"]
			order.shuffle()
			for what in order:
				var before: int = p.industry
				if what == "outpost" and p.industry >= GameState.OUTPOST_COST:
					var os = s.outpost_spots(p)
					if not os.is_empty() and s.player_build_outpost(os.pick_random()): stats["outposts: you"] += 1
				elif what == "scout": s.player_build_scout()
				elif what == "army" and s.food_change(p) > 0: s.player_build_unit()
				elif what == "walls" and s.turn >= 8: s.player_build_walls()
				if p.industry != before: break
				H.answer_choices(s)
			# --- move: scouts explore, spare armies guard an outpost
			for u in p.units.duplicate():
				if not u in p.units: continue
				while u in p.units and u.moves > 0 and not s.is_waiting():
					var goal := HexMap.NO_CELL
					if u.is_scout():
						goal = explore_goal(s, u)
					elif u.pos != p.city_pos:
						for o in p.outposts:
							if s.unit_at(o) == null: goal = o; break
					if goal == HexMap.NO_CELL or goal == u.pos: break
					var step: Vector2i = s.step_toward(u.pos, goal)
					if step == HexMap.NO_CELL or s.war_target(step) != null: break
					if not s.player_unit_act(u, step): break
					for msg in s.messages:
						if msg.begins_with("You took the"): stats["you took one"] += 1
					if H.answer_choices(s) > 0: stats["ruins: you"] += 1
			if s.turn < 14 and not p.known_rifts.is_empty() and not s.has_meta("rift"):
				s.set_meta("rift", true); stats["rifts found before turn 14"] += 1
			var turn_before: int = s.turn
			var pending_before: int = s.pending_choices.size()
			s.messages.clear()
			s.end_turn()
			if not s.game_over and s.turn != turn_before + 1: bad["turn didn't advance"] = bad.get("turn didn't advance", 0) + 1
			if s.pending_choices.size() > pending_before and s.pending_choices[-1]["title"] != "RUINS": stats["events"] += 1
			if s.has_pending_offer():
				s.pending_relation().answer(randf() < 0.5)
			for msg in s.messages:
				if "took your outpost" in msg: stats["your outposts taken"] += 1
				if "BROKE THEIR" in msg: stats["ai betrayals"] += 1
				for a in ["Japanese", "Celtic", "Greek"]:
					for b in ["Japanese", "Celtic", "Greek"]:
						if a != b and msg.begins_with("%s attacked %s" % [a, b]): stats["ai vs ai fights"] += 1
			# --- impossible states
			var seen := {}
			for f in s.factions:
				if f.food < 0 or f.industry < 0: bad["negative stores"] = bad.get("negative stores", 0) + 1
				if not f.is_alive() and (f.units.size() > 0 or f.outposts.size() > 0): bad["fallen faction still has things"] = 1
				if f.scout_count() > GameState.MAX_SCOUTS: bad["too many scouts"] = 1
				for u in f.units:
					if seen.has(u.pos) or not HexMap.in_bounds(u.pos) or s.skoll.is_at(u.pos): bad["unit position"] = bad.get("unit position", 0) + 1
					if not s.passable(u.pos): bad["unit on mountain or water"] = bad.get("unit on mountain or water", 0) + 1
					seen[u.pos] = true
					if s.is_city(u.pos) and u.pos != f.city_pos: bad["unit in someone else's city"] = bad.get("unit in someone else's city", 0) + 1
					if u.moves < 0 or u.moves > u.max_moves(): bad["moves out of range"] = 1
				for o in f.outposts:
					if s.is_city(o): bad["outpost on a city"] = 1
					if not s.passable(o): bad["outpost on mountain or water"] = 1
					if s.outpost_owner(o) != f: bad["outpost with two owners"] = 1
				# everything a faction can see must be explored
				for row in HexMap.ROWS:
					for col in HexMap.COLS:
						var c := Vector2i(col, row)
						if s.can_see(f, c) and not f.explored.has(c): bad["seen but not explored"] = bad.get("seen but not explored", 0) + 1
			for r in s.rifts.cells:
				if not s.passable(r): bad["rift on mountain or water"] = 1
			for r in s.ruins:
				if not s.passable(r["cell"]): bad["ruins on mountain or water"] = 1
			if s.daughter.is_rogue() and not s.passable(s.daughter.pos): bad["daughter in a lake"] = 1
			var all_outposts := []
			for f in s.factions: all_outposts.append_array(f.outposts)
			for i in all_outposts.size():
				for j in range(i + 1, all_outposts.size()):
					if HexMap.hex_distance(all_outposts[i], all_outposts[j]) < GameState.OUTPOST_MIN_DISTANCE: bad["outposts too close"] = 1
			if s.player.explored.size() < last_explored: bad["explored shrank"] = 1
			last_explored = s.player.explored.size()
			if s.turn == 10: explored_by_10 += s.player.explored.size()
			if s.turn > 40: bad["game never ended"] = 1; break
		var taken: int = s.ruins.filter(func(r): return r["taken"]).size()
		stats["ruins: ai"] += taken
		for f in s.ais: stats["outposts: ai"] += f.outposts.size()
		ends[s.end_title] = ends.get(s.end_title, 0) + 1
		m.queue_free()
	stats["ruins: ai"] -= stats["ruins: you"]
	print("Endings (300 games): %s" % ends)
	print("Turns 1-10: %d turns, with a pop-up %d%%, something to build %d%%, a scout with land to explore %d%%; turns with NO decision: %d" % [early_turns, roundi(100.0 * kinds["pop-up"] / early_turns), roundi(100.0 * kinds["build"] / early_turns), roundi(100.0 * kinds["scout"] / early_turns), dead_turns])
	print("Average hexes explored by turn 10: %d of %d" % [roundi(float(explored_by_10) / 300), HexMap.ROWS * HexMap.COLS])
	print("Per game: events %.1f, ruins searched by you %.1f / by AIs %.1f, outposts you founded %.1f, AI outposts standing at the end %.1f, your outposts taken %.2f, you took one %.2f" % [stats["events"] / float(n_games), stats["ruins: you"] / float(n_games), stats["ruins: ai"] / float(n_games), stats["outposts: you"] / float(n_games), stats["outposts: ai"] / float(n_games), stats["your outposts taken"] / float(n_games), stats["you took one"] / float(n_games)])
	print("Games where you found a rift before Sköll arrived: %d; games where you could build on turn 1: %d" % [stats["rifts found before turn 14"], stats["turn-1 builds possible"]])
	print("AI betrayals per game %.2f, AI-vs-AI fights per game %.1f" % [stats["ai betrayals"] / float(n_games), stats["ai vs ai fights"] / float(n_games)])
	print("Impossible states: %s" % (bad if bad.size() > 0 else "none"))
	quit()
