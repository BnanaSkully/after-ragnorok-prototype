extends SceneTree
const H := preload("res://tests/helpers.gd")
# Playing in the 3D view: clicking (press and release) selects a unit, shows where
# it can go (click3d_selected.png), moves it, and places an outpost
# (click3d_outpost.png). A rift's hollow next to water stays dry (click3d_rift.png).
# Prints OK/BAD lines. Needs a window (not --headless). Saved to $S.
var m
var v
func shot(file: String) -> void:
	for i in 3: await process_frame
	root.get_texture().get_image().save_png("%s/%s" % [OS.get_environment("S"), file])
func click(cell: Vector2i) -> void:
	var at: Vector2 = v.camera.unproject_position(v.cell_position(cell) + Vector3(0, v.hex_top(cell), 0))
	Input.warp_mouse(at)
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.position = at; e.global_position = at
		Input.parse_input_event(e)
		for i in 3: await process_frame
func check(ok: bool, what: String) -> void:
	print(("OK   " if ok else "BAD  ") + what)
func _initialize() -> void:
	seed(7)
	m = load("res://main.tscn").instantiate()
	root.add_child(m)
	for i in 3: await process_frame
	var s = m.state
	for step in 4: s.choose(s.Crossing.EVENTS[step]["choices"][0]["effects"])
	H.flatten(s)
	s.start_landing()
	s.try_land(H.landing_spots(s)[0])
	H.answer_choices(s)
	var home: Vector2i = s.player.city_pos
	# water beside a known rift, to see the hollow stays dry
	var rift: Vector2i = home + Vector2i(3, 0)
	s.player.known_rifts[rift] = true
	for n in HexMap.neighbours(rift):
		if HexMap.hex_distance(n, home) > 2:
			s.terrain[n] = Terrain.Type.WATER
	s.player.industry = 30
	s.reveal_area(s.player, home, 6)
	s.update_sight(); m.refresh()
	m.toggle_3d()
	v = m.view_3d
	v.cam_target = v.cell_position(home); v.cam_distance = 9.0; v.place_camera()
	for i in 20: await process_frame
	var unit = s.player.units[0]
	var round_trip := 0
	var on_screen := 0
	for c in v.hexes:
		var p: Vector3 = v.cell_position(c) + Vector3(0, v.MODEL_GROUND, 0)
		if v.camera.is_position_in_frustum(p):
			on_screen += 1
			if v.cell_at_screen(v.camera.unproject_position(p)) == c:
				round_trip += 1
	check(on_screen > 0 and round_trip == on_screen, "cell_at_screen finds the hex under the mouse (%d of %d hexes on screen)" % [round_trip, on_screen])
	await click(unit.pos)
	check(m.selected == unit, "clicking your unit selects it")
	await shot("click3d_selected.png")
	var target := HexMap.NO_CELL
	for n in HexMap.neighbours(unit.pos):
		if s.passable(n) and s.unit_at(n) == null and not s.is_city(n):
			target = n
			break
	var from: Vector2i = unit.pos
	await click(target)
	check(unit.pos == target and from != target, "clicking a hex next to it moves it there")
	var before: int = s.player.outposts.size()
	m.placing_outpost = true
	m.refresh()
	for i in 5: await process_frame
	var spots: Array = s.outpost_spots(s.player)
	await shot("click3d_outpost.png")
	if not spots.is_empty():
		await click(spots[0])
	check(s.player.outposts.size() == before + 1, "clicking an outpost spot founds an outpost (%d spots)" % spots.size())
	# a drag (press here, release far away) is not a click
	m.selected = null
	var at: Vector2 = v.camera.unproject_position(v.cell_position(s.player.units[0].pos))
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.position = at + (Vector2(80, 0) if not pressed else Vector2.ZERO)
		Input.parse_input_event(e)
		for i in 3: await process_frame
	check(m.selected == null, "dragging is not a click")
	# Sköll: stands on his hex facing his prey; beaten, he sinks away; back through a
	# far rift, he appears there instead of drifting across the map
	var w = s.skoll
	w.active = true
	w.target = s.player
	w.pos = home + Vector2i(2, 1)
	s.update_sight()
	v.cam_target = v.cell_position(w.pos); v.cam_distance = 7.0; v.place_camera()
	for i in 10: await process_frame
	var want: Vector3 = v.cell_position(home) - v.cell_position(w.pos)
	check(absf(wrapf(v.skoll.rotation.y - atan2(want.x, want.z), -PI, PI)) < 0.01, "Sköll faces the city he hunts")
	check(absf(v.skoll.position.y - (v.hex_top(w.pos) + v.skoll_feet)) < 0.01, "Sköll stands on his hex's ground")
	await shot("click3d_skoll.png")
	w.drive_back()
	for i in 90: await process_frame
	check(not v.skoll.visible, "beaten, Sköll sinks away and is gone")
	var far: Vector2i = home + Vector2i(-2, -1) # in sight of your city, 4 hexes from where he fell
	s.reveal_area(s.player, far, 1)
	w.active = true
	w.pos = far
	s.update_sight()
	for i in 2: await process_frame
	check(v.skoll.position.distance_to(v.cell_position(far) + Vector3(0, v.hex_top(far) + v.skoll_feet, 0)) < 0.01, "back through a rift, he appears there at once")
	v.cam_target = v.cell_position(rift); v.cam_distance = 5.0; v.place_camera()
	for i in 10: await process_frame
	await shot("click3d_rift.png")
	quit()
