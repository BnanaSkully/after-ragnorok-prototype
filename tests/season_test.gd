extends SceneTree
const H := preload("res://tests/helpers.gd")

# Full rifts step 3: the season (Rifts.SEASON_*). Part 1: the calendar for
# turns 1-40. Part 2: a real game's messages (warning the turn before, start,
# end) and the goal line. Run: godot --headless --script tests/season_test.gd

func _initialize() -> void:
	await process_frame
	var on: Array[int] = []
	for t in range(1, 41):
		if Rifts.season_on(t): on.append(t)
	print("1. season turns %s (expect [7, 8, 14, 15, 21, 22, 28, 29, 35, 36])" % [on])
	print("   turns left on 7, 8: %d, %d (expect 2, 1); next season after 1, 8, 9, 36: %d, %d, %d, %d (expect 7, 14, 14, 42)" % [Rifts.season_left(7), Rifts.season_left(8), Rifts.next_season(1), Rifts.next_season(8), Rifts.next_season(9), Rifts.next_season(36)])
	seed(5)
	var m = load("res://main.tscn").instantiate()
	root.add_child(m)
	var s = m.state
	for step in 4: s.choose(s.Crossing.EVENTS[step]["choices"][0]["effects"])
	H.flatten(s); s.start_landing(); s.try_land(Vector2i(6, 4))
	var said := {}
	var goal_in_season := []
	while s.turn < 16 and not s.game_over:
		H.answer_choices(s)
		s.end_turn()
		if s.has_pending_offer(): s.pending_relation().answer(false)
		for line in s.messages:
			if "begins next turn" in line: said[s.turn] = said.get(s.turn, []) + ["warning"]
			if "has begun" in line: said[s.turn] = said.get(s.turn, []) + ["start"]
			if "has passed" in line: said[s.turn] = said.get(s.turn, []) + ["end"]
		H.answer_choices(s)
		if s.has_pending_offer(): s.pending_relation().answer(false)
		if Rifts.season_on(s.turn): goal_in_season.append(m.season_line().begins_with(Rifts.season_title()))
	print("2. messages by turn %s (expect 6 warning, 7 start, 9 end, 13 warning, 14 start, 16 end)" % [said])
	print("   status line names the season on every season turn: %s (expect all true)" % [goal_in_season])
	m.queue_free()
	quit()
