extends SceneTree
const H := preload("res://tests/helpers.gd")
# You are the Japanese tributary, the Greek are yours, and your army stands
# next to the Celtic city (at war) with another army beside it: the city lights
# up to attack. Saves tribute.png to $S.
var m
func click_at(pos: Vector2) -> void:
	Input.warp_mouse(pos)
	for i in 3: await process_frame
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT; e.pressed = pressed; e.position = pos; e.global_position = pos
		Input.parse_input_event(e)
		for i in 3: await process_frame
func _initialize() -> void:
	seed(4)
	m = load("res://main.tscn").instantiate()
	root.add_child(m)
	for i in 3: await process_frame
	var s = m.state
	for step in 4: s.choose(s.Crossing.EVENTS[step]["choices"][0]["effects"])
	H.flatten(s); s.start_landing(); s.try_land(Vector2i(6, 4))
	var jp = s.ais[0]; var celtic = s.ais[1]; var greek = s.ais[2]
	s.make_tributary(s.player, jp)
	s.make_tributary(greek, s.player)
	s.relation(celtic).player_declare_war()
	var spots = HexMap.neighbours(celtic.city_pos).filter(func(c): return s.unit_at(c) == null)
	var a = s.player.units[0]; a.pos = spots[0]; a.moves = 1
	s.player.add_unit(spots[1])
	for c in HexMap.neighbours(celtic.city_pos): s.reveal_area(s.player, c, 1)
	s.update_sight(); m.refresh()
	await click_at(HexView2D.hex_center(a.pos))
	print("selected=%s; your attack on the Celtic city: %d vs defence %d (%s)" % [m.selected != null, s.siege_strength(a, celtic), s.city_defence(celtic), s.odds_text(s.win_chance(s.siege_strength(a, celtic), s.city_defence(celtic)))])
	for i in 4: await process_frame
	root.get_texture().get_image().save_png("%s/tribute.png" % OS.get_environment("S"))
	quit()
