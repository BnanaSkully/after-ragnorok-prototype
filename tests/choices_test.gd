extends SceneTree
const H := preload("res://tests/helpers.gd")
const TurnEvents := preload("res://turn_events.gd")
const Discoveries := preload("res://discoveries.gd")
# Ruins and small events: no option that can't do anything (Favour already at
# 10), every option of every event costs something, and every event can always
# be answered.
func new_game():
	var m = load("res://main.tscn").instantiate()
	root.add_child(m)
	var s = m.state
	for step in 4: s.choose(s.Crossing.EVENTS[step]["choices"][0]["effects"])
	H.flatten(s); s.start_landing(); s.try_land(Vector2i(6, 4))
	return m

# What an option costs (a list of words; empty = free).
func costs_of(effects: Dictionary) -> Array:
	var c := []
	for k in ["food", "industry", "favour", "population"]:
		if effects.get(k, 0) < 0: c.append(k)
	if effects.has("gamble"): c.append("risk")
	if effects.has("guard_turns"): c.append("a unit's turns")
	return c

func _initialize() -> void:
	await process_frame
	seed(3)
	var m = new_game(); var s = m.state
	s.player.favour = 10
	var ruin = Discoveries.ruin_choice(s)
	print("1. ruins with her Favour at 10: options %s" % [ruin["options"].map(func(o): return o["label"])])
	print("   any option still offering Favour: %s (expect false)" % ruin["options"].any(func(o): return o["effects"].get("favour", 0) > 0))
	s.player.favour = 5
	ruin = Discoveries.ruin_choice(s)
	print("   with Favour 5 the shrine is offered: %s" % ruin["options"].any(func(o): return o["effects"].get("favour", 0) > 0))
	s.player.favour = 10; s.player.food = 20
	print("2. a Favour gain at Favour 10: problem '%s'" % s.option_problem({"food": -4, "favour": 1}))
	# 3. every event: every option costs something; at least one option is always possible
	var free := []; var stuck := []
	for e in TurnEvents.EVENTS:
		for o in e["options"]:
			if costs_of(o["effects"]).is_empty(): free.append("%s: %s" % [e["title"], o["label"]])
		for fav in [0, 10]:
			s.player.food = 0; s.player.industry = 0; s.player.favour = fav
			for u in s.player.units.duplicate(): s.player.remove_unit(u)
			if not e["options"].any(func(o): return s.can_afford(o["effects"])): stuck.append("%s (favour %d, nothing in store, no units)" % [e["title"], fav])
	print("3. options that cost nothing: %s" % [free if free.size() > 0 else "none"])
	print("   events with no possible answer when you have nothing: %s" % [stuck if stuck.size() > 0 else "none"])
	m.queue_free()
	quit()
